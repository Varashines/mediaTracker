import SwiftUI
import Combine
import UniformTypeIdentifiers
import os
import CryptoKit

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

/// Thread-safe dictionary for urlToKeys, accessible from both @MainActor and nonisolated contexts.
private final class URLToKeysStore: @unchecked Sendable {
    private var dict: [String: Set<String>] = [:]
    private let lock = OSAllocatedUnfairLock(uncheckedState: ())

    func get(_ url: String) -> Set<String>? {
        lock.withLockUnchecked { dict[url] }
    }

    func insert(_ url: String, _ key: String) {
        lock.withLockUnchecked {
            if dict[url] == nil { dict[url] = [] }
            dict[url]?.insert(key)
        }
    }

    func remove(_ url: String) {
        lock.withLockUnchecked { _ = dict.removeValue(forKey: url) }
    }

    func removeKey(_ url: String, _ key: String) {
        lock.withLockUnchecked {
            if var keys = dict[url] {
                keys.remove(key)
                if keys.isEmpty { dict.removeValue(forKey: url) } else { dict[url] = keys }
            }
        }
    }

    func removeAll() {
        lock.withLockUnchecked { dict.removeAll() }
    }
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
    // Thread-safe: accessible from both @MainActor and NSCache delegate (arbitrary thread)
    private let urlToKeys = URLToKeysStore()
    
    // Phase 3 Optimization: In-Memory Disk Cache Index
    private var diskCacheIndex: Set<String> = []
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var saveCount: Int64 = 0

    // Detection for Retina displays
    private let screenScale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0
    
    private let cacheDirectory: URL
    let imageSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 10
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

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
        
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("MediaTracker", isDirectory: true)
        self.cacheDirectory = appSupport.appendingPathComponent("CachedImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        
        super.init()
        
        // Delegate to clean up urlToKeys leak
        self.memoryCache.delegate = self
        
        // Asynchronous Disk Indexing
        let dir = self.cacheDirectory
        Task.detached(priority: .userInitiated) {
            let fileURLs = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            let keys = Set(fileURLs.map { $0.lastPathComponent })
            await MainActor.run {
                ImageCache.shared.diskCacheIndex = keys
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
            self.urlToKeys.removeAll()
            self.memoryCache.removeAllObjects()
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
    
    func clearDiskIndex() {
        diskCacheIndex.removeAll()
    }
    
    private static func fileSafeKey(_ string: String) -> String {
        // Use SHA256 for a stable hash across process launches (unlike hashValue which is not guaranteed stable)
        let inputData = Data(string.utf8)
        let digest = SHA256.hash(data: inputData)
        let hashString = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        let escaped = string.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return "\(hashString)_\(escaped.prefix(80))"
    }

    func removeImage(forKey url: String?) async {
        guard let url, !url.isEmpty else { return }
        
        if let keys = urlToKeys.get(url) {
            for key in keys {
                memoryCache.removeObject(forKey: key as NSString)
            }
            urlToKeys.remove(url)
        }
        
        let fileKey = Self.fileSafeKey(url)
        let fileURL = self.cacheDirectory.appendingPathComponent(fileKey)
        Task.detached(priority: .background) {
            try? FileManager.default.removeItem(at: fileURL)
            await MainActor.run {
                _ = ImageCache.shared.diskCacheIndex.remove(fileKey)
            }
        }
    }
    
    func clearFullCache() {
        clearMemoryCache()
        
        let dir = self.cacheDirectory
        Task.detached(priority: .userInitiated) {
            let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
            await MainActor.run {
                self.diskCacheIndex.removeAll()
                self.updates.send("CLEARED_ALL")
            }
        }
    }

    func clearCache(forURLs urls: [String]) {
        let hashes = urls.map { url in
            let h = Self.fileSafeKey(url)
            
            if let keys = urlToKeys.get(url) {
                for key in keys {
                    memoryCache.removeObject(forKey: key as NSString)
                }
                urlToKeys.remove(url)
            }
            return h
        }
        
        if hashes.isEmpty { return }

        let dir = self.cacheDirectory
        Task.detached(priority: .userInitiated) {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                let name = file.lastPathComponent
                if hashes.contains(where: { name.hasPrefix($0) }) {
                    try? FileManager.default.removeItem(at: file)
                    await MainActor.run {
                        _ = ImageCache.shared.diskCacheIndex.remove(name)
                    }
                }
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
        if let keys = urlToKeys.get(key) {
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
        let hash = Self.fileSafeKey(key)
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
                let (data, _) = try await self.imageSession.data(from: url)
                if Task.isCancelled { return }
                
                guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else { return }
                
                // Save to disk in background (don't block memory cache)
                await self.save(imageSource: imageSource, data: data, forKey: key, targetSize: targetSize, alwaysPreserveAlpha: alwaysPreserveAlpha)
                
                if Task.isCancelled { return }

                // Decode directly from downloaded data instead of re-reading from disk
                let decodedImage: CGImage?
                if let targetSize = targetSize {
                    let maxDimension = max(targetSize.width, targetSize.height) * self.screenScale
                    let downsampleOptions = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: maxDimension
                    ] as CFDictionary
                    decodedImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions)
                } else {
                    decodedImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
                }
                
                if let cgImage = decodedImage {
                    let wrapper = CachedImageWrapper(image: cgImage, urlString: key, cacheKey: specificKey)
                    self.memoryCache.setObject(wrapper, forKey: specificKey as NSString, cost: self.cost(for: cgImage))
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
        urlToKeys.insert(url, specificKey)
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
        let fileURL = self.cacheDirectory.appendingPathComponent(diskFileName)
        
        await Task.detached(priority: .background) {
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
                        try? savedData.write(to: fileURL)
                    }
                } else {
                    try? rawData.write(to: fileURL)
                }
                await Task.yield()
            } else {
                try? rawData.write(to: fileURL)
            }

            await MainActor.run {
                _ = ImageCache.shared.diskCacheIndex.insert(diskFileName)
            }

            let count = await MainActor.run { ImageCache.shared.saveCount += 1; return ImageCache.shared.saveCount }
            if count % 50 == 0 {
                await ImageCache.shared.pruneDiskCacheIfNeeded()
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
        let dir = self.cacheDirectory
        let maxDiskCacheSize = self.maxDiskCacheSize
        await Task.detached(priority: .background) {
            let fileManager = FileManager.default
            let urls = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
            
            var totalSize: Int64 = 0
            var files: [(URL, Date, Int64)] = []
            
            for url in urls {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                if let date = values?.contentModificationDate, let size = values?.fileSize {
                    let fileSize = Int64(size)
                    totalSize += fileSize
                    files.append((url, date, fileSize))
                }
            }
            
            if totalSize > maxDiskCacheSize {
                let sorted = files.sorted(by: { $0.1 < $1.1 })
                var currentSize = totalSize
                for (url, _, size) in sorted {
                    if currentSize <= (maxDiskCacheSize * 8 / 10) { break }
                    try? fileManager.removeItem(at: url)
                    currentSize -= size
                    let name = url.lastPathComponent
                    await MainActor.run {
                        _ = ImageCache.shared.diskCacheIndex.remove(name)
                    }
                    await Task.yield()
                }
            }
        }.value
    }

    private func loadFromDisk(diskFileName: String, targetSize: CGSize?) async -> ImageContainer? {
        let screenScale = self.screenScale
        let fileURL = self.cacheDirectory.appendingPathComponent(diskFileName)
        return await Task.detached(priority: .userInitiated) {
            // Use CGImageSourceCreateWithURL to let CoreGraphics memory-map the file
            // instead of loading entire Data into RAM before decoding
            guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
            
            if let targetSize = targetSize {
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
            
            guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { return nil }
            return ImageContainer(image: cgImage)
        }.value
    }
}

extension ImageCache: NSCacheDelegate {
    nonisolated func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let wrapper = obj as? CachedImageWrapper else { return }
        // Synchronous cleanup via thread-safe store — avoids async dispatch lag where stale keys persist
        urlToKeys.removeKey(wrapper.urlString, wrapper.cacheKey)
    }
}

