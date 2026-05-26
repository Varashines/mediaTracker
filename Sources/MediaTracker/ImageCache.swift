import SwiftUI
import CryptoKit
import Combine
import UniformTypeIdentifiers
import SwiftData

struct ImageContainer: @unchecked Sendable {
    let image: CGImage
}

final class CachedImageWrapper: NSObject, @unchecked Sendable {
    let image: CGImage
    let urlString: String
    let cacheKey: String

    init(image: CGImage, urlString: String, cacheKey: String) {
        self.image = image
        self.urlString = urlString
        self.cacheKey = cacheKey
        super.init()
    }
}

enum ImagePriority {
    case low, normal, critical
}

@MainActor
class ImageCache: NSObject {
    static let shared = ImageCache()
    
    // Performance: Prioritize small memory cache for 8GB M1 Macs
    private let memoryCache = NSCache<NSString, CachedImageWrapper>()
    private let maxDiskCacheSize: Int64 = 500 * 1024 * 1024 // 500MB
    
    // Notification for broadcast updates
    let updates = PassthroughSubject<String, Never>()
    
    // Task de-duplication registry - NOW TRACKING URL + SIZE
    private var activeTasks: [String: Task<Void, Never>] = [:]
    
    // Reverse lookup to find ANY size of an image URL in memory
    private var urlToKeys: [String: Set<String>] = [:]
    
    // Phase 3 Optimization: In-Memory Disk Cache Index
    private var diskCacheIndex: Set<String> = []
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    // Detection for Retina displays
    private let screenScale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0
    
    private let dbContainer: ModelContainer

    private override init() {
        // Adaptive memory cache sizing based on system RAM
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        if physicalMemory >= 16_000_000_000 {
            memoryCache.totalCostLimit = 256 * 1024 * 1024
            memoryCache.countLimit = 1500
        } else if physicalMemory >= 8_000_000_000 {
            memoryCache.totalCostLimit = 128 * 1024 * 1024
            memoryCache.countLimit = 800
        } else {
            memoryCache.totalCostLimit = 64 * 1024 * 1024
            memoryCache.countLimit = 400
        }
        
        // Initialize SwiftData SQLite DB for images
        let schema = Schema([ImageCacheEntity.self])
        let cacheURL = URL.applicationSupportDirectory.appendingPathComponent("ImageCacheStore.sqlite")
        let config = ModelConfiguration(schema: schema, url: cacheURL, allowsSave: true)
        do {
            self.dbContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("CRITICAL: Failed to initialize ImageCache ModelContainer. Error: \(error)")
        }
        
        super.init()
        
        // Phase 3 Fix: Delegate to clean up urlToKeys leak
        self.memoryCache.delegate = self
        
        // Phase 2 Optimization: Asynchronous Disk Indexing
        let container = self.dbContainer
        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<ImageCacheEntity>()
            if let entities = try? context.fetch(descriptor) {
                let keys = Set(entities.map { $0.id })
                await MainActor.run {
                    ImageCache.shared.diskCacheIndex = keys
                }
            }
        }
        
        Task.detached(priority: .background) {
            await ImageCache.shared.pruneDiskCacheIfNeeded()
        }
        
        // Memory Pressure Monitoring
        let memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        memoryPressureSource.setEventHandler { [weak self] in
            let event = memoryPressureSource.data
            self?.handleMemoryPressure(event: event)
        }
        memoryPressureSource.resume()
        self.memoryPressureSource = memoryPressureSource
    }
    
    /// macOS 26 Tahoe inspired Memory Compaction
    @MainActor
    func performMemoryCompaction(level: MemoryPressureLevel) {
        switch level {
        case .warning:
            self.memoryCache.totalCostLimit = 80 * 1024 * 1024
            self.memoryCache.countLimit = 150
        case .critical:
            self.memoryCache.totalCostLimit = 10 * 1024 * 1024
            self.memoryCache.countLimit = 10
            self.memoryCache.removeAllObjects()
            self.urlToKeys.removeAll()
        }
        Task {
            await APIClient.shared.clearMemoryCaches()
        }
    }
    
    private func handleMemoryPressure(event: DispatchSource.MemoryPressureEvent) {
        switch event {
        case .warning:
            performMemoryCompaction(level: .warning)
        case .critical:
            performMemoryCompaction(level: .critical)
        default:
            break
        }
    }
    
    enum MemoryPressureLevel {
        case warning, critical
    }
    
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
        urlToKeys.removeAll()
    }
    
    private static func sha256Hash(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func removeImage(forKey url: String?) async {
        guard let url, !url.isEmpty else { return }
        let hash = Self.sha256Hash(url)
        
        if let keys = urlToKeys[url] {
            for key in keys {
                memoryCache.removeObject(forKey: key as NSString)
            }
            urlToKeys.removeValue(forKey: url)
        }
        
        let container = self.dbContainer
        Task.detached(priority: .background) {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<ImageCacheEntity>(predicate: #Predicate { $0.id == hash })
            if let entity = try? context.fetch(descriptor).first {
                context.delete(entity)
                try? context.save()
            }
            await MainActor.run {
                _ = ImageCache.shared.diskCacheIndex.remove(hash)
            }
        }
    }
    
    func clearFullCache() {
        clearMemoryCache()
        
        let container = self.dbContainer
        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            try? context.delete(model: ImageCacheEntity.self)
            try? context.save()
            
            await MainActor.run {
                self.diskCacheIndex.removeAll()
                // Force UI to refresh existing views
                self.updates.send("CLEARED_ALL")
            }
        }
    }

    func clearCache(forURLs urls: [String]) {
        let hashes = urls.map { url in
            let h = Self.sha256Hash(url)
            
            if let keys = urlToKeys[url] {
                for key in keys {
                    memoryCache.removeObject(forKey: key as NSString)
                }
                urlToKeys.removeValue(forKey: url)
            }
            return h
        }
        
        if hashes.isEmpty { return }

        // 2. Disk Clear
        let container = self.dbContainer
        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<ImageCacheEntity>()
            if let entities = try? context.fetch(descriptor) {
                for entity in entities {
                    if hashes.contains(where: { entity.id.hasPrefix($0) }) {
                        let id = entity.id
                        context.delete(entity)
                        await MainActor.run {
                            _ = ImageCache.shared.diskCacheIndex.remove(id)
                        }
                    }
                }
                try? context.save()
            }
            
            await MainActor.run {
                for url in urls {
                    self.updates.send(url)
                }
            }
        }
    }
    
    func checkMemoryCache(forKey key: String, targetSize: CGSize?) -> ImageContainer? {
        let specificKey = targetSize.map { "\(key)_\(Int($0.width))x\(Int($0.height))" } ?? key
        if let wrapper = memoryCache.object(forKey: specificKey as NSString) {
            return ImageContainer(image: wrapper.image)
        }
        
        // Return ANY size to let standard scale aspect fill, avoiding black layouts
        if let keys = urlToKeys[key] {
            let matches = keys.compactMap { k -> (String, CGImage)? in
                if let wrapper = memoryCache.object(forKey: k as NSString) {
                    return (k, wrapper.image)
                }
                return nil
            }
            
            if let target = targetSize {
                let largerMatch = matches.first { (k, img) in
                    CGFloat(img.width) >= target.width * screenScale && 
                    CGFloat(img.height) >= target.height * screenScale
                }
                if let best = largerMatch {
                    return ImageContainer(image: best.1)
                }
            }

            // Fallback: Return the largest available (even if smaller) for a fuzzy match
            let sorted = matches.sorted { $0.1.width > $1.1.width }
            if let best = sorted.first {
                return ImageContainer(image: best.1)
            }
        }
        
        return nil
    }

    private func generateCacheKey(key: String, size: CGSize?) -> String {
        guard let size = size else { return key }
        return "\(key)_\(Int(size.width))x\(Int(size.height))"
    }
    
    private func fileName(for key: String, size: CGSize?) -> String {
        let hash = Self.sha256Hash(key)
        if let size = size {
            return "\(hash)_\(Int(size.width))_\(Int(size.height))"
        }
        return "\(hash)"
    }

    func cancel(forKey key: String, targetSize: CGSize? = nil) {
        let fullKey = generateCacheKey(key: key, size: targetSize)
        activeTasks[fullKey]?.cancel()
        activeTasks[fullKey] = nil
    }

    func get(forKey key: String, targetSize: CGSize? = nil, priority: ImagePriority = .normal, alwaysPreserveAlpha: Bool = false) async -> ImageContainer? {
        // 1. Memory Check
        let specificKey = generateCacheKey(key: key, size: targetSize)
        if let wrapper = memoryCache.object(forKey: specificKey as NSString) {
            return ImageContainer(image: wrapper.image)
        }
        
        // 2. Coalesce tasks by the SPECIFIC key (URL + Size) to prevent duplicate downloads
        if let existingTask = activeTasks[specificKey] {
            await existingTask.value
            // Re-check memory after shared task finishes
            if let wrapper = memoryCache.object(forKey: specificKey as NSString) {
                return ImageContainer(image: wrapper.image)
            }
        }
        
        if Task.isCancelled { return nil }

        let task = Task { [weak self] in
            guard let self = self else { return }
            let diskFileName = self.fileName(for: key, size: targetSize)
            
            // Try disk (Optimized via Index)
            if self.diskCacheIndex.contains(diskFileName) {
                if let container = await self.loadFromDisk(diskFileName: diskFileName, targetSize: targetSize) {
                    if Task.isCancelled { return }
                    let wrapper = CachedImageWrapper(image: container.image, urlString: key, cacheKey: specificKey)
                    self.memoryCache.setObject(wrapper, forKey: specificKey as NSString, cost: self.cost(for: container.image))
                    self.registerKeyForURL(key, specificKey: specificKey)
                    self.updates.send(key) 
                    return
                }
            }
            
            if Task.isCancelled { return }

            // Download logic
            do {
                guard let url = URL(string: key) else { return }
                let (data, _) = try await URLSession.shared.data(from: url)
                if Task.isCancelled { return }
                
                guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else { return }
                
                await self.save(imageSource: imageSource, data: data, forKey: key, targetSize: targetSize, alwaysPreserveAlpha: alwaysPreserveAlpha)
                
                if Task.isCancelled { return }

                // Re-load decoded version after save to verify
                if let container = await self.loadFromDisk(diskFileName: diskFileName, targetSize: targetSize) {
                    let wrapper = CachedImageWrapper(image: container.image, urlString: key, cacheKey: specificKey)
                    self.memoryCache.setObject(wrapper, forKey: specificKey as NSString, cost: self.cost(for: container.image))
                    self.registerKeyForURL(key, specificKey: specificKey)
                    self.updates.send(key)
                }
            } catch {
                if !(error is CancellationError) {
                    AppLogger.warning("Download error: \(error)", logger: AppLogger.cache)
                }
            }
        }
        
        activeTasks[specificKey] = task
        defer { activeTasks[specificKey] = nil }
        await task.value
        
        if let wrapper = memoryCache.object(forKey: specificKey as NSString) {
            return ImageContainer(image: wrapper.image)
        }
        return nil
    }
    
    private func registerKeyForURL(_ url: String, specificKey: String) {
        if urlToKeys[url] == nil { urlToKeys[url] = [] }
        urlToKeys[url]?.insert(specificKey)
    }

    private func cost(for image: CGImage) -> Int {
        return image.bytesPerRow * image.height
    }

    func ping(url: String) {
        updates.send(url)
    }

    func isExactMatch(image: CGImage, forURL url: String, size: CGSize?) -> Bool {
        let specificKey = generateCacheKey(key: url, size: size)
        if memoryCache.object(forKey: specificKey as NSString)?.image === image {
            return true
        }
        
        // Aggressive exact match: if the image we have is actually larger than the target,
        // we treat it as an exact match to skip the blur.
        if let target = size {
            return CGFloat(image.width) >= target.width * screenScale && 
                   CGFloat(image.height) >= target.height * screenScale
        }
        
        return false
    }

    @discardableResult
    func prewarmImages(urls: [URL], targetSize: CGSize, priority: ImagePriority = .low) -> Task<Void, Never> {
        let taskPriority: TaskPriority = priority == .critical ? .userInitiated : .background
        return Task.detached(priority: taskPriority) {
            await withTaskGroup(of: Void.self) { group in
                for url in urls {
                    if Task.isCancelled { break }
                    group.addTask {
                        _ = await ImageCache.shared.get(forKey: url.absoluteString, targetSize: targetSize, priority: priority)
                    }
                }
            }
        }
    }
    
    func save(imageSource: CGImageSource, data: Data? = nil, forKey key: String, targetSize: CGSize? = nil, alwaysPreserveAlpha: Bool = false) async {
        guard let rawData = data else { return }
        let diskFileName = fileName(for: key, size: targetSize)
        let screenScale = self.screenScale
        let container = self.dbContainer
        
        await Task.detached(priority: .background) {
            let context = ModelContext(container)
            guard let taskImageSource = CGImageSourceCreateWithData(rawData as CFData, nil) else { return }
            
            if let targetSize = targetSize {
                let maxDimension = max(targetSize.width, targetSize.height) * screenScale
                let downsampleOptions = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxDimension
                ] as CFDictionary
                
                if let downsampledCG = CGImageSourceCreateThumbnailAtIndex(taskImageSource, 0, downsampleOptions) {
                    let alpha = downsampledCG.alphaInfo
                    let hasAlpha = alpha != .none && alpha != .noneSkipLast && alpha != .noneSkipFirst && alpha != .alphaOnly
                    let usePNG = alwaysPreserveAlpha || hasAlpha
                    
                    if let savedData = Self.writeToDataStatic(image: downsampledCG, usePNG: usePNG) {
                        let entity = ImageCacheEntity(id: diskFileName, data: savedData, accessDate: Date(), size: Int64(savedData.count))
                        context.insert(entity)
                    }
                } else {
                    let entity = ImageCacheEntity(id: diskFileName, data: rawData, accessDate: Date(), size: Int64(rawData.count))
                    context.insert(entity)
                }
                await Task.yield()
            } else {
                let entity = ImageCacheEntity(id: diskFileName, data: rawData, accessDate: Date(), size: Int64(rawData.count))
                context.insert(entity)
            }
            
            try? context.save()

            await MainActor.run {
                _ = ImageCache.shared.diskCacheIndex.insert(diskFileName)
            }
        }.value
    }
    
    private static nonisolated func writeToDataStatic(image: CGImage, usePNG: Bool) -> Data? {
        let type = usePNG ? UTType.png.identifier : UTType.jpeg.identifier
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type as CFString, 1, nil) else { return nil }
        
        if usePNG {
            CGImageDestinationAddImage(destination, image, nil)
        } else {
            let properties = [kCGImageDestinationLossyCompressionQuality: 0.90] as CFDictionary
            CGImageDestinationAddImage(destination, image, properties)
        }
        CGImageDestinationFinalize(destination)
        return data as Data
    }
    
    nonisolated func pruneDiskCacheIfNeeded() async {
        let container = self.dbContainer
        let maxDiskCacheSize = self.maxDiskCacheSize
        await Task.detached(priority: .background) {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<ImageCacheEntity>()
            guard let entities = try? context.fetch(descriptor) else { return }
            
            var totalSize: Int64 = 0
            for entity in entities {
                totalSize += entity.size
            }
            
            if totalSize > maxDiskCacheSize {
                let sortedEntities = entities.sorted(by: { $0.accessDate < $1.accessDate })
                var currentSize = totalSize
                for entity in sortedEntities {
                    if currentSize <= (maxDiskCacheSize * 8 / 10) { break }
                    let id = entity.id
                    context.delete(entity)
                    currentSize -= entity.size
                    
                    await MainActor.run {
                        _ = ImageCache.shared.diskCacheIndex.remove(id)
                    }
                    await Task.yield()
                }
                try? context.save()
            }
        }.value
    }

    private func loadFromDisk(diskFileName: String, targetSize: CGSize?) async -> ImageContainer? {
        let screenScale = self.screenScale
        let container = self.dbContainer
        return await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<ImageCacheEntity>(predicate: #Predicate { $0.id == diskFileName })
            guard let entity = try? context.fetch(descriptor).first else { return nil }
            
            let data = entity.data
            
            if let targetSize = targetSize {
                let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                if let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) {
                    let maxDimension = max(targetSize.width, targetSize.height) * screenScale
                    let downsampleOptions = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: maxDimension
                    ] as CFDictionary
                    
                    if let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) {
                        return ImageContainer(image: cgImage)
                    }
                }
            }
            
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { return nil }
            return ImageContainer(image: cgImage)
        }.value
    }
}

extension ImageCache: NSCacheDelegate {
    nonisolated func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let wrapper = obj as? CachedImageWrapper else { return }
        let url = wrapper.urlString
        let key = wrapper.cacheKey
        
        Task { @MainActor in
            if var keys = urlToKeys[url] {
                keys.remove(key)
                if keys.isEmpty {
                    urlToKeys.removeValue(forKey: url)
                } else {
                    urlToKeys[url] = keys
                }
            }
        }
    }
}

