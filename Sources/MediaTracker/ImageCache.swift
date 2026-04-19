import SwiftUI
import CryptoKit
import Combine

struct ImageContainer: @unchecked Sendable {
    let image: CGImage
}

@globalActor
actor DiskIOActor {
    static let shared = DiskIOActor()
    private var activeCount = 0
    private let maxConcurrentReads = 4

    func run<T>(priority: TaskPriority? = nil, operation: @escaping @Sendable () async throws -> T) async rethrows -> T {
        while activeCount >= maxConcurrentReads {
            await Task.yield()
        }
        activeCount += 1
        defer { activeCount -= 1 }
        return try await operation()
    }
}

@MainActor
class ImageCache {
    static let shared = ImageCache()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let memoryCache = NSCache<NSString, CGImage>()
    private let maxDiskCacheSize: Int64 = 150 * 1024 * 1024 
    
    // Broadcast system for live updates
    private let updateSubject = PassthroughSubject<String, Never>()
    var updates: AnyPublisher<String, Never> { updateSubject.eraseToAnyPublisher() }

    // Task de-duplication registry - NOW TRACKING BASE URL
    private var activeTasks: [String: Task<Void, Never>] = [:]
    
    // Reverse lookup to find ANY size of an image URL in memory
    private var urlToKeys: [String: Set<String>] = [:]

    // Detection for Retina displays
    private let screenScale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0

    private init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let basePath = paths.first ?? fileManager.temporaryDirectory
        let cacheDir = basePath.appendingPathComponent("mediatracker_images")
        self.cacheDirectory = cacheDir
        
        if !fileManager.fileExists(atPath: cacheDir.path) {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        
        memoryCache.countLimit = 200 
        
        Task.detached(priority: .background) {
            await ImageCache.shared.pruneDiskCacheIfNeeded()
        }
    }
    
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
        urlToKeys.removeAll()
    }
    
    func checkMemoryCache(forKey key: String, targetSize: CGSize? = nil) -> ImageContainer? {
        let specificKey = generateCacheKey(key: key, size: targetSize)
        
        // 1. Check for the exact size
        if let image = memoryCache.object(forKey: specificKey as NSString) {
            return ImageContainer(image: image)
        }
        
        // 2. Fuzzy Match: Check if ANY version of this URL is in memory
        if let keys = urlToKeys[key] {
            let availableImages = keys.compactMap { memoryCache.object(forKey: $0 as NSString) }
            if let bestMatch = availableImages.sorted(by: { $0.width > $1.width }).first {
                return ImageContainer(image: bestMatch)
            }
        }
        
        return nil
    }

    private func generateCacheKey(key: String, size: CGSize?) -> String {
        guard let size = size else { return key }
        let physicalWidth = Int(size.width * screenScale)
        let physicalHeight = Int(size.height * screenScale)
        return "\(key)_\(physicalWidth)x\(physicalHeight)"
    }
    
    private func fileName(for key: String, size: CGSize?) -> String {
        let cacheKey = generateCacheKey(key: key, size: size)
        let inputData = cacheKey.count > 0 ? Data(cacheKey.utf8) : Data()
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func loadFromDisk(fileURL: URL, targetSize: CGSize?) async -> ImageContainer? {
        await DiskIOActor.shared.run {
            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return nil }
            
            let physicalSize = targetSize != nil ? max(targetSize!.width, targetSize!.height) * self.screenScale : 600
            let maxPixelSize = Int(physicalSize)
            
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            
            return ImageContainer(image: cgImage)
        }
    }

    enum ImagePriority {
        case critical, normal, low
    }

    func get(forKey key: String, targetSize: CGSize? = nil, priority: ImagePriority = .normal) async -> ImageContainer? {
        // 1. Memory Check
        let specificKey = generateCacheKey(key: key, size: targetSize)
        if let image = memoryCache.object(forKey: specificKey as NSString) {
            return ImageContainer(image: image)
        }
        
        // 2. Coalesce tasks by the BASE URL to prevent duplicate downloads
        if let existingTask = activeTasks[key] {
            await existingTask.value
            // Re-check memory after shared task finishes
            if let image = memoryCache.object(forKey: specificKey as NSString) {
                return ImageContainer(image: image)
            }
        }
        
        let task = Task { [weak self] in
            guard let self = self else { return }
            let diskFileName = fileName(for: key, size: targetSize)
            let fileURL = cacheDirectory.appendingPathComponent(diskFileName)
            
            // Try disk
            if let container = await loadFromDisk(fileURL: fileURL, targetSize: targetSize) {
                self.memoryCache.setObject(container.image, forKey: specificKey as NSString)
                self.registerKeyForURL(key, specificKey: specificKey)
                self.updateSubject.send(key) 
                return
            }
            
            // Download logic
            do {
                guard let url = URL(string: key) else { return }
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let nsImage = NSImage(data: data) else { return }
                
                await self.save(image: nsImage, data: data, forKey: key, targetSize: targetSize)
                
                // Re-load decoded version after save to verify
                if let container = await loadFromDisk(fileURL: fileURL, targetSize: targetSize) {
                    self.memoryCache.setObject(container.image, forKey: specificKey as NSString)
                    self.registerKeyForURL(key, specificKey: specificKey)
                    self.updateSubject.send(key)
                }
            } catch {
                print("Download error: \(error)")
            }
        }
        
        activeTasks[key] = task
        await task.value
        activeTasks[key] = nil
        
        if let image = memoryCache.object(forKey: specificKey as NSString) {
            return ImageContainer(image: image)
        }
        return nil
    }
    
    private func registerKeyForURL(_ url: String, specificKey: String) {
        if urlToKeys[url] == nil { urlToKeys[url] = [] }
        urlToKeys[url]?.insert(specificKey)
    }

    func ping(url: String) {
        updateSubject.send(url)
    }

    func isExactMatch(image: CGImage, forURL url: String, size: CGSize?) -> Bool {
        let specificKey = generateCacheKey(key: url, size: size)
        return memoryCache.object(forKey: specificKey as NSString) === image
    }

    func prewarmImages(urls: [URL], targetSize: CGSize, priority: ImagePriority = .low) {
        Task {
            await withTaskGroup(of: Void.self) { group in
                for url in urls {
                    group.addTask {
                        _ = await self.get(forKey: url.absoluteString, targetSize: targetSize, priority: priority)
                    }
                }
            }
        }
    }
    
    func save(image: NSImage, data: Data? = nil, forKey key: String, targetSize: CGSize? = nil) async {
        let rawData = data
        let diskFileName = fileName(for: key, size: targetSize)
        let diskCacheDir = cacheDirectory
        
        // Only decode for memory cache if we don't have a CGImage yet
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let tinyProxyFileName = fileName(for: key, size: CGSize(width: 50, height: 50))
        
        await Task.detached(priority: .background) {
            let fileURL = diskCacheDir.appendingPathComponent(diskFileName)
            
            // PASS-THROUGH: Write raw data directly if available and no resizing needed
            if let data = rawData, targetSize == nil {
                try? data.write(to: fileURL)
            } else if let cg = cgImage {
                // Resize or re-encode if necessary
                let bitmap = NSBitmapImageRep(cgImage: cg)
                let dataToWrite = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
                try? dataToWrite?.write(to: fileURL)
            }
            
            // Save tiny proxy (Always downsampled)
            if let cg = cgImage {
                let proxyURL = diskCacheDir.appendingPathComponent(tinyProxyFileName)
                let tinySize = NSSize(width: 50, height: 75)
                let tinyImage = NSImage(size: tinySize)
                tinyImage.lockFocus()
                NSImage(cgImage: cg, size: .zero).draw(in: NSRect(origin: .zero, size: tinySize))
                tinyImage.unlockFocus()
                if let tinyTiff = tinyImage.tiffRepresentation,
                   let tinyBitmap = NSBitmapImageRep(data: tinyTiff) {
                    let tinyData = tinyBitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.4])
                    try? tinyData?.write(to: proxyURL)
                }
            }
        }.value
    }
    
    func pruneDiskCacheIfNeeded() async {
        let resourceKeys: [URLResourceKey] = [.fileSizeKey, .contentAccessDateKey]
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: resourceKeys, options: []) else { return }
        
        var totalSize: Int64 = 0
        var fileInfos: [(url: URL, size: Int64, date: Date)] = []
        for fileURL in files {
            let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys))
            let size = Int64(values?.fileSize ?? 0)
            let date = values?.contentAccessDate ?? Date.distantPast
            totalSize += size
            fileInfos.append((fileURL, size, date))
        }
        
        if totalSize > maxDiskCacheSize {
            let sortedFiles = fileInfos.sorted(by: { $0.date < $1.date })
            var currentSize = totalSize
            for file in sortedFiles {
                if currentSize <= (maxDiskCacheSize * 8 / 10) { break }
                try? fileManager.removeItem(at: file.url)
                currentSize -= file.size
            }
        }
    }
}

struct CachedImage<Placeholder: View>: View {
    let url: URL?
    let targetSize: CGSize?
    let priority: ImageCache.ImagePriority
    var onImageLoaded: ((CGImage) -> Void)? = nil
    @ViewBuilder let placeholder: Placeholder
    
    @State private var image: CGImage?
    @State private var fuzzyMatch: CGImage?
    @State private var isLoading = false
    @State private var broadcastCancellable: AnyCancellable?

    init(url: URL?, targetSize: CGSize? = nil, priority: ImageCache.ImagePriority = .normal, onImageLoaded: ((CGImage) -> Void)? = nil, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.targetSize = targetSize
        self.priority = priority
        self.onImageLoaded = onImageLoaded
        self.placeholder = placeholder()
        
        // 1. SYNCHRONOUS SNAP: Check cache immediately in initializer
        if let url = url, let container = ImageCache.shared.checkMemoryCache(forKey: url.absoluteString, targetSize: targetSize) {
            let isExact = ImageCache.shared.isExactMatch(image: container.image, forURL: url.absoluteString, size: targetSize)
            if isExact {
                _image = State(initialValue: container.image)
            } else {
                _fuzzyMatch = State(initialValue: container.image)
            }
        }
    }
    
    var body: some View {
        Group {
            if SleepManager.shared.isAsleep {
                staticPlaceholder
            } else if let finalImage = image {
                Image(finalImage, scale: 1.0, label: Text(""))
                    .resizable()
                    .transition(.opacity)
            } else if let lowRes = fuzzyMatch {
                Image(lowRes, scale: 1.0, label: Text(""))
                    .resizable()
                    .blur(radius: 4)
                    .transition(.opacity)
            } else {
                staticPlaceholder
            }
        }
        .animation(.easeIn(duration: 0.25), value: image == nil)
        .onAppear {
            // 2. LISTEN-FIRST: Setup listener before any loading begins
            setupBroadcastListener()
            
            if image == nil {
                Task { await attemptLoad() }
            }
        }
        .task(id: url) {
            // Safety re-check on URL change
            await attemptLoad()
        }
        .onChange(of: SleepManager.shared.isAsleep) { oldValue, isAsleep in
            if isAsleep {
                self.image = nil
                self.fuzzyMatch = nil
                self.broadcastCancellable?.cancel()
            } else {
                setupBroadcastListener()
                Task { await attemptLoad() }
            }
        }
    }

    @ViewBuilder
    private var staticPlaceholder: some View {
        ZStack {
            Color.secondary.opacity(0.1)
            placeholder
        }
    }

    private func setupBroadcastListener() {
        guard let url = url else { return }
        let key = url.absoluteString
        
        broadcastCancellable?.cancel()
        broadcastCancellable = ImageCache.shared.updates
            .filter { $0 == key }
            .receive(on: DispatchQueue.main)
            .sink { _ in
                Task { await attemptLoad() }
            }
    }

    private func attemptLoad() async {
        guard let url = url else { return }
        let key = url.absoluteString
        
        if let container = ImageCache.shared.checkMemoryCache(forKey: key, targetSize: targetSize) {
            let isExact = ImageCache.shared.isExactMatch(image: container.image, forURL: key, size: targetSize)
            
            if isExact {
                withAnimation(.easeIn(duration: 0.2)) {
                    self.image = container.image
                    self.fuzzyMatch = nil
                }
            } else {
                self.fuzzyMatch = container.image
                await loadImage()
            }
        } else {
            // Tiny Proxy check
            if let tiny = ImageCache.shared.checkMemoryCache(forKey: key, targetSize: CGSize(width: 50, height: 50)) {
                self.fuzzyMatch = tiny.image
            }
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard let url = url, !isLoading else { return }
        let key = url.absoluteString
        
        isLoading = true
        defer { isLoading = false }

        if let container = await ImageCache.shared.get(forKey: key, targetSize: targetSize, priority: priority) {
            if Task.isCancelled { return }
            withAnimation(.easeIn(duration: 0.25)) {
                self.image = container.image
                self.fuzzyMatch = nil
            }
            onImageLoaded?(container.image)
        }
    }
}
