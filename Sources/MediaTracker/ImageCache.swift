import SwiftUI
import CryptoKit
import Combine
import UniformTypeIdentifiers

struct ImageContainer: @unchecked Sendable {
    let image: CGImage
}

@globalActor
actor DiskIOActor {
    static let shared = DiskIOActor()
    private var activeCount = 0
    private let maxConcurrent = 6 // Increased from 3 to 6

    func run<T>(_ work: @Sendable () async throws -> T) async rethrows -> T {
        while activeCount >= maxConcurrent {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        activeCount += 1
        defer { activeCount -= 1 }
        return try await work()
    }
}

@MainActor
@Observable
class ImageCache {
    static let shared = ImageCache()
    
    // Performance: Prioritize small memory cache for 8GB M1 Macs
    private let memoryCache = NSCache<NSString, CGImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let maxDiskCacheSize: Int64 = 500 * 1024 * 1024 // Increased to 500MB
    
    // Notification for broadcast updates
    let updates = PassthroughSubject<String, Never>()
    
    // Task de-duplication registry - NOW TRACKING URL + SIZE
    private var activeTasks: [String: Task<Void, Never>] = [:]
    
    // Reverse lookup to find ANY size of an image URL in memory
    private var urlToKeys: [String: Set<String>] = [:]
    
    // Phase 3 Optimization: In-Memory Disk Cache Index
    private var diskCacheIndex: Set<String> = []

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
        
        // Cost-based memory limit (approx 256MB for thumbnails - safe for 8GB+ Macs)
        memoryCache.totalCostLimit = 256 * 1024 * 1024
        memoryCache.countLimit = 300 // Higher count limit for small thumbnails
        // Phase 1 Optimization: Asynchronous Disk Indexing (M1 Startup Fix)
        Task.detached(priority: .background) {
            let fm = FileManager.default
            if let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) {
                let fileNames = Set(files.map { $0.lastPathComponent })
                await MainActor.run {
                    ImageCache.shared.diskCacheIndex = fileNames
                }
            }
        }
        
        // Dynamic Resource Management
        NotificationCenter.default.addObserver(forName: .memoryPressureWarning, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.performMemoryCompaction(level: .warning) }
        }
        
        NotificationCenter.default.addObserver(forName: .memoryPressureCritical, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.performMemoryCompaction(level: .critical) }
        }

        Task.detached(priority: .background) {
            await ImageCache.shared.pruneDiskCacheIfNeeded()
        }
    }
    
    /// macOS 26 Tahoe inspired Memory Compaction
    @MainActor
    private func performMemoryCompaction(level: MemoryPressureLevel) {
        switch level {
        case .warning:
            // Prune to 40MB
            self.memoryCache.totalCostLimit = 40 * 1024 * 1024
            self.memoryCache.countLimit = 50
        case .critical:
            self.memoryCache.totalCostLimit = 10 * 1024 * 1024
            self.memoryCache.countLimit = 10
            self.memoryCache.removeAllObjects()
            self.urlToKeys.removeAll()
            // Force a sync to disk for any pending metadata
            NotificationCenter.default.post(name: NSNotification.Name("ForceSwiftDataSave"), object: nil)
        }
    }
    
    enum MemoryPressureLevel {
        case warning, critical
    }
    
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
        urlToKeys.removeAll()
    }
    
    func clearFullCache() {
        clearMemoryCache()
        
        // Purge disk
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let files = (try? fm.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                try? fm.removeItem(at: file)
            }
            
            await MainActor.run {
                self.diskCacheIndex.removeAll()
                // Force UI to refresh existing views
                self.updates.send("CLEARED_ALL")
            }
        }
    }

    func clearCache(forURLs urls: [String]) {
        let hashes = urls.map { url in
            let h = SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
            
            // 1. Memory Clear
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
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let files = (try? fm.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                let fileName = file.lastPathComponent
                if hashes.contains(where: { fileName.hasPrefix($0) }) {
                    try? fm.removeItem(at: file)
                    await MainActor.run {
                        _ = ImageCache.shared.diskCacheIndex.remove(fileName)
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
        // 1. Exact size match
        let specificKey = generateCacheKey(key: key, size: targetSize)
        if let exact = memoryCache.object(forKey: specificKey as NSString) {
            return ImageContainer(image: exact)
        }
        
        // 2. Fuzzy match (Any size already in memory for this URL)
        if let keys = urlToKeys[key] {
            // Prefer largest available
            let sortedKeys = keys.sorted { $0.count > $1.count }
            if let bestMatchKey = sortedKeys.first,
               let bestMatch = memoryCache.object(forKey: bestMatchKey as NSString) {
                return ImageContainer(image: bestMatch)
            }
        }
        
        return nil
    }

    private func generateCacheKey(key: String, size: CGSize?) -> String {
        guard let size = size else { return key }
        return "\(key)_\(Int(size.width))x\(Int(size.height))"
    }
    
    private func fileName(for key: String, size: CGSize?) -> String {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        if let size = size {
            return "\(hash)_\(Int(size.width))_\(Int(size.height)).jpg"
        }
        return "\(hash).jpg"
    }

    func getTinyProxy(forKey key: String) async -> ImageContainer? {
        let tinySize = CGSize(width: 50, height: 75)
        let tinyKey = generateCacheKey(key: key, size: tinySize)
        
        // 1. Memory Check
        if let image = memoryCache.object(forKey: tinyKey as NSString) {
            return ImageContainer(image: image)
        }
        
        // 2. Disk Check (Optimized via Index)
        let diskFileName = fileName(for: key, size: tinySize)
        guard diskCacheIndex.contains(diskFileName) else { return nil }
        
        let fileURL = cacheDirectory.appendingPathComponent(diskFileName)
        
        if let container = await loadFromDisk(fileURL: fileURL, targetSize: tinySize) {
            memoryCache.setObject(container.image, forKey: tinyKey as NSString, cost: cost(for: container.image))
            registerKeyForURL(key, specificKey: tinyKey)
            return container
        }
        
        return nil
    }

    func cancel(forKey key: String, targetSize: CGSize? = nil) {
        let fullKey = generateCacheKey(key: key, size: targetSize)
        activeTasks[fullKey]?.cancel()
        activeTasks[fullKey] = nil
    }

    func get(forKey key: String, targetSize: CGSize? = nil, priority: ImagePriority = .normal, alwaysPreserveAlpha: Bool = false) async -> ImageContainer? {
        // 1. Memory Check
        let specificKey = generateCacheKey(key: key, size: targetSize)
        if let image = memoryCache.object(forKey: specificKey as NSString) {
            return ImageContainer(image: image)
        }
        
        // 2. Coalesce tasks by the SPECIFIC key (URL + Size) to prevent duplicate downloads
        if let existingTask = activeTasks[specificKey] {
            await existingTask.value
            // Re-check memory after shared task finishes
            if let image = memoryCache.object(forKey: specificKey as NSString) {
                return ImageContainer(image: image)
            }
        }
        
        if Task.isCancelled { return nil }

        let task = Task { [weak self] in
            guard let self = self else { return }
            let diskFileName = self.fileName(for: key, size: targetSize)
            let fileURL = self.cacheDirectory.appendingPathComponent(diskFileName)
            
            // Try disk (Optimized via Index)
            if self.diskCacheIndex.contains(diskFileName) {
                if let container = await self.loadFromDisk(fileURL: fileURL, targetSize: targetSize) {
                    if Task.isCancelled { return }
                    self.memoryCache.setObject(container.image, forKey: specificKey as NSString, cost: self.cost(for: container.image))
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
                
                // Phase 3 Optimization: Directly work with CGImageSource to avoid NSImage overhead
                guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else { return }
                
                await self.save(imageSource: imageSource, data: data, forKey: key, targetSize: targetSize, alwaysPreserveAlpha: alwaysPreserveAlpha)
                
                if Task.isCancelled { return }

                // Re-load decoded version after save to verify
                if let container = await self.loadFromDisk(fileURL: fileURL, targetSize: targetSize) {
                    self.memoryCache.setObject(container.image, forKey: specificKey as NSString, cost: self.cost(for: container.image))
                    self.registerKeyForURL(key, specificKey: specificKey)
                    self.updates.send(key)
                }
            } catch {
                if !(error is CancellationError) {
                    print("Download error: \(error)")
                }
            }
        }
        
        activeTasks[specificKey] = task
        await task.value
        activeTasks[specificKey] = nil
        
        if let image = memoryCache.object(forKey: specificKey as NSString) {
            return ImageContainer(image: image)
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
    
    func save(imageSource: CGImageSource, data: Data? = nil, forKey key: String, targetSize: CGSize? = nil, alwaysPreserveAlpha: Bool = false) async {
        guard let rawData = data else { return }
        let diskFileName = fileName(for: key, size: targetSize)
        let diskCacheDir = cacheDirectory
        let screenScale = self.screenScale
        let tinyProxyFileName = fileName(for: key, size: CGSize(width: 50, height: 75))
        
        await Task.detached(priority: .background) {
            let fileURL = diskCacheDir.appendingPathComponent(diskFileName)
            
            // Re-create imageSource inside task to avoid capturing main-actor isolated object
            guard let taskImageSource = CGImageSourceCreateWithData(rawData as CFData, nil) else { return }
            
            // Phase 3 Optimization: Downsample and encode using CGImageDestination (Platform Agnostic)
            if let targetSize = targetSize {
                let maxDimension = max(targetSize.width, targetSize.height) * screenScale
                let downsampleOptions = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxDimension
                ] as CFDictionary
                
                if let downsampledCG = CGImageSourceCreateThumbnailAtIndex(taskImageSource, 0, downsampleOptions) {
                    let hasAlpha = downsampledCG.alphaInfo != .none && downsampledCG.alphaInfo != .noneSkipLast && downsampledCG.alphaInfo != .noneSkipFirst
                    let usePNG = alwaysPreserveAlpha || hasAlpha
                    
                    Self.writeToDiskStatic(image: downsampledCG, to: fileURL, usePNG: usePNG)
                } else {
                    try? rawData.write(to: fileURL)
                }
            } else {
                try? rawData.write(to: fileURL)
            }
            
            // Save tiny proxy (Always downsampled)
            let tinyMaxDim: CGFloat = 75 * screenScale
            let tinyOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: tinyMaxDim
            ] as CFDictionary
            
            if let tinyCG = CGImageSourceCreateThumbnailAtIndex(taskImageSource, 0, tinyOptions) {
                let proxyURL = diskCacheDir.appendingPathComponent(tinyProxyFileName)
                Self.writeToDiskStatic(image: tinyCG, to: proxyURL, usePNG: false)
                
                await MainActor.run {
                    _ = ImageCache.shared.diskCacheIndex.insert(tinyProxyFileName)
                }
            }

            await MainActor.run {
                _ = ImageCache.shared.diskCacheIndex.insert(diskFileName)
            }
        }.value
    }
    
    private static nonisolated func writeToDiskStatic(image: CGImage, to url: URL, usePNG: Bool) {
        let type = usePNG ? UTType.png.identifier : UTType.jpeg.identifier
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else { return }
        
        if usePNG {
            CGImageDestinationAddImage(destination, image, nil)
        } else {
            let properties = [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
            CGImageDestinationAddImage(destination, image, properties)
        }
        CGImageDestinationFinalize(destination)
    }
    
    nonisolated func pruneDiskCacheIfNeeded() async {
        let resourceKeys: [URLResourceKey] = [.fileSizeKey, .contentAccessDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: resourceKeys, options: []) else { return }
        
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
                try? FileManager.default.removeItem(at: file.url)
                currentSize -= file.size
                
                let fileName = file.url.lastPathComponent
                await MainActor.run {
                    _ = ImageCache.shared.diskCacheIndex.remove(fileName)
                }
            }
        }
    }

    private func loadFromDisk(fileURL: URL, targetSize: CGSize?) async -> ImageContainer? {
        let screenScale = self.screenScale
        return await DiskIOActor.shared.run {
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            
            if let targetSize = targetSize {
                let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                if let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) {
                    let maxDimension = max(targetSize.width, targetSize.height) * screenScale
                    let downsampleOptions = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceShouldCacheImmediately: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: maxDimension
                    ] as CFDictionary
                    
                    if let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) {
                        return ImageContainer(image: cgImage)
                    }
                }
            }
            
            // Fallback for missing targetSize or failed downsample
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { return nil }
            return ImageContainer(image: cgImage)
        }
    }

    enum ImagePriority {
        case low, normal, critical
    }
}

struct CachedImage<Placeholder: View>: View {
    let url: URL?
    let targetSize: CGSize?
    let priority: ImageCache.ImagePriority
    var themeColor: Color? = nil
    var isFastScrolling: Bool = false
    var alwaysPreserveAlpha: Bool = false
    var onImageLoaded: ((CGImage) -> Void)? = nil
    @ViewBuilder let placeholder: Placeholder
    
    @State private var image: CGImage?
    @State private var fuzzyMatch: CGImage?
    @State private var isLoading = false
    @State private var broadcastCancellable: AnyCancellable?

    init(url: URL?, targetSize: CGSize? = nil, priority: ImageCache.ImagePriority = .normal, themeColor: Color? = nil, isFastScrolling: Bool = false, alwaysPreserveAlpha: Bool = false, onImageLoaded: ((CGImage) -> Void)? = nil, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.targetSize = targetSize
        self.priority = priority
        self.themeColor = themeColor
        self.isFastScrolling = isFastScrolling
        self.alwaysPreserveAlpha = alwaysPreserveAlpha
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
            if SleepManager.shared.isAsleep || (isFastScrolling && image == nil && fuzzyMatch == nil) {
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
        .animation(.smooth(duration: 0.2), value: image == nil)
        .onAppear {
            // 2. LISTEN-FIRST: Setup listener before any loading begins
            setupBroadcastListener()
            
            if image == nil && !isFastScrolling {
                Task { await attemptLoad() }
            }
        }
        .onDisappear {
            if let url = url {
                ImageCache.shared.cancel(forKey: url.absoluteString, targetSize: targetSize)
            }
        }
        .task(id: url) {
            // Safety re-check on URL change
            if !isFastScrolling {
                await attemptLoad()
            }
        }
        .onChange(of: isFastScrolling) { oldValue, newValue in
            if !newValue && image == nil {
                Task { await attemptLoad() }
            }
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
        if let color = themeColor {
            Rectangle()
                .fill(color.opacity(0.15))
                .overlay {
                    Image(systemName: "film")
                        .foregroundStyle(color.opacity(0.3))
                        .font(.system(size: 24))
                }
        } else {
            ZStack {
                Color.secondary.opacity(0.1)
                placeholder
            }
        }
    }

    private func setupBroadcastListener() {
        guard let url = url else { return }
        let key = url.absoluteString
        
        broadcastCancellable?.cancel()
        broadcastCancellable = ImageCache.shared.updates
            .filter { $0 == key || $0 == "CLEARED_ALL" }
            .receive(on: DispatchQueue.main)
            .sink { _ in
                // If the whole cache was cleared, we MUST drop local state
                if ImageCache.shared.checkMemoryCache(forKey: key, targetSize: targetSize) == nil {
                    self.image = nil
                    self.fuzzyMatch = nil
                }
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
                return
            } else {
                self.fuzzyMatch = container.image
            }
        }
        
        // Fetch Tiny Proxy (Disk check included in getTinyProxy)
        if fuzzyMatch == nil {
            if let container = await ImageCache.shared.getTinyProxy(forKey: key) {
                withAnimation(.easeIn(duration: 0.2)) {
                    self.fuzzyMatch = container.image
                }
            }
        }
        
        await loadImage()
    }
    
    private func loadImage() async {
        guard let url = url, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        
        if let container = await ImageCache.shared.get(forKey: url.absoluteString, targetSize: targetSize, priority: priority, alwaysPreserveAlpha: alwaysPreserveAlpha) {
            if Task.isCancelled { return }
            withAnimation(.easeIn(duration: 0.25)) {
                self.image = container.image
                self.fuzzyMatch = nil
            }
            onImageLoaded?(container.image)
        }
    }
}
