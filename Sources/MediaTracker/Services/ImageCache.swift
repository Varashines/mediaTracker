import SwiftUI
import AppKit
import os

extension Notification.Name {
    static let imageCacheCleared = Notification.Name("MediaTracker.imageCacheCleared")
}

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
class ImageCache: NSObject, NSCacheDelegate {
    static let shared = ImageCache()
    
    /// Network session used for image downloads (e.g. logo color extraction).
    /// Swappable via `configureForTesting(session:)` so tests can stub it with
    /// `MockURLProtocol` instead of hitting the network.
    nonisolated(unsafe) var imageSession: URLSession = .shared

    /// Replaces the image download session. Test-only; restores the system
    /// session when passed nil.
    func configureForTesting(session: URLSession? = nil) {
        imageSession = session ?? .shared
    }
    
    private let memoryCache = NSCache<NSString, CachedImageWrapper>()
    private var activeTasks: [String: Task<ImageContainer?, Never>] = [:]
    private let maxConcurrentLoads = 6
    private let currentLoads = OSAllocatedUnfairLock<Int>(uncheckedState: 0)
    
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    private override init() {
        super.init()
        memoryCache.delegate = self
        // Adaptive sizing by RAM — matches ARCHITECTURE.md spec
        let ram = ProcessInfo.processInfo.physicalMemory
        if ram >= 16 * 1024 * 1024 * 1024 {
            memoryCache.countLimit = 1500
            memoryCache.totalCostLimit = 256 * 1024 * 1024
        } else if ram >= 8 * 1024 * 1024 * 1024 {
            memoryCache.countLimit = 800
            memoryCache.totalCostLimit = 128 * 1024 * 1024
        } else {
            memoryCache.countLimit = 400
            memoryCache.totalCostLimit = 64 * 1024 * 1024
        }

        // Clear memory cache on memory pressure to free up system resources
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            self?.clearMemoryCache()
        }
        source.resume()
        memoryPressureSource = source
    }
    
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }
    
    func clearDiskIndex() {
        URLCache.shared.removeAllCachedResponses()
    }
    
    func clearFullCache() {
        clearMemoryCache()
        clearDiskIndex()
        NotificationCenter.default.post(name: .imageCacheCleared, object: nil)
    }
    
    func removeImage(forKey url: String?) async {
        guard let url = url else { return }
        memoryCache.removeObject(forKey: url as NSString)
        if let nsURL = URL(string: url) {
            let request = URLRequest(url: nsURL)
            URLCache.shared.removeCachedResponse(for: request)
        }
    }
    
    func evictOffscreenImage(forKey key: String?, targetSize: CGSize? = nil) {
        guard let key = key, !key.isEmpty else { return }
        let cacheKey = generateCacheKey(key: key, size: targetSize)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            // Skip eviction if the image is being actively re-requested — e.g. the
            // cell scrolled back into view while this task was waiting. Evicting it
            // would force a wasteful re-decode on scrub-back.
            guard activeTasks[cacheKey] == nil else { return }
            self.memoryCache.removeObject(forKey: cacheKey as NSString)
        }
    }
    
    func checkMemoryCache(forKey key: String, targetSize: CGSize?) -> ImageContainer? {
        let cacheKey = generateCacheKey(key: key, size: targetSize)
        if let wrapper = memoryCache.object(forKey: cacheKey as NSString) {
            return ImageContainer(image: wrapper.image)
        }
        return nil
    }
    
    private func generateCacheKey(key: String, size: CGSize?) -> String {
        if let size = size {
            return "\(key)_\(Int(size.width))x\(Int(size.height))"
        }
        return key
    }
    
    func cancel(forKey key: String, targetSize: CGSize? = nil) {
        let cacheKey = generateCacheKey(key: key, size: targetSize)
        activeTasks[cacheKey]?.cancel()
        activeTasks[cacheKey] = nil
    }
    
    func prewarmImages(urls: [URL], targetSize: CGSize? = nil, priority: ImagePriority = .normal) {
        guard !urls.isEmpty else { return }
        let maxConcurrent = priority == .critical ? 8 : 4
        var index = 0
        var inFlight = 0

        func loadNext() {
            while index < urls.count, inFlight < maxConcurrent {
                let url = urls[index]
                index += 1
                let key = url.absoluteString
                let cacheKey = generateCacheKey(key: key, size: targetSize)
                // Skip if already cached or actively loading
                if checkMemoryCache(forKey: key, targetSize: targetSize) != nil || activeTasks[cacheKey] != nil {
                    continue
                }
                inFlight += 1
                let task = Task.detached(priority: priority == .low ? .utility : .userInitiated) { [weak self] in
                    _ = await self?.get(forKey: key, targetSize: targetSize, priority: priority)
                }
                Task {
                    _ = await task.value
                    await MainActor.run {
                        inFlight -= 1
                        loadNext()
                    }
                }
            }
        }
        loadNext()
    }
    
    func prewarmImages(_ metadata: [MediaThumbnailMetadata], limit: Int = 10, targetSize: CGSize? = nil, priority: ImagePriority = .normal) {
        let urls = metadata.prefix(limit).compactMap { $0.posterURL }.compactMap { URL(string: $0) }
        prewarmImages(urls: urls, targetSize: targetSize, priority: priority)
    }
    
    func get(forKey key: String, targetSize: CGSize? = nil, priority: ImagePriority = .normal, alwaysPreserveAlpha: Bool = false) async -> ImageContainer? {
        let cacheKey = generateCacheKey(key: key, size: targetSize)
        
        if let cached = checkMemoryCache(forKey: key, targetSize: targetSize) {
            return cached
        }
        
        if let active = activeTasks[cacheKey] {
            return await active.value
        }
        
        // Throttle concurrent loads to prevent bursts on cold start
        while true {
            let acquired = currentLoads.withLock { current -> Bool in
                guard current < maxConcurrentLoads else { return false }
                current += 1
                return true
            }
            if acquired { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        
        // Capture session + lock strongly so decrement always runs even if self deallocates
        let capturedSession = self.imageSession
        let loadsLock = self.currentLoads
        let task = Task<ImageContainer?, Never> { [weak self] in
            defer {
                loadsLock.withLock { $0 -= 1 }
            }
            guard let self = self else { return nil }
            guard let url = URL(string: key) else { return nil }
            
            do {
                let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 15.0)
                let (data, response) = try await capturedSession.data(for: request)
                
                if Task.isCancelled { return nil }
                
                // Decode off the main actor to avoid blocking UI
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                let finalCGImage: CGImage? = await Task.detached(priority: .utility) { [scale] in
                    if key.lowercased().hasSuffix(".svg") || (response.mimeType?.contains("svg") ?? false) {
                        return Self.renderSVGToCGImage(data: data, targetSize: targetSize)
                    } else if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                        if let target = targetSize {
                            let maxDimension = max(target.width, target.height) * scale
                            let options: [CFString: Any] = [
                                kCGImageSourceShouldCache: false,
                                kCGImageSourceCreateThumbnailFromImageAlways: true,
                                kCGImageSourceCreateThumbnailWithTransform: true,
                                kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension)
                            ]
                            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                        } else {
                            return CGImageSourceCreateImageAtIndex(source, 0, nil)
                        }
                    }
                    return nil
                }.value
                
                if let cgImage = finalCGImage {
                    let wrapper = CachedImageWrapper(image: cgImage, urlString: key, cacheKey: cacheKey)
                    self.memoryCache.setObject(wrapper, forKey: cacheKey as NSString, cost: cgImage.bytesPerRow * cgImage.height)

                    // Populate the cache even if the requesting cell scrolled away — the image
                    // is fully decoded, so discarding it forces a wasteful re-decode on scrub-back.
                    if Task.isCancelled { return nil }

                    return ImageContainer(image: cgImage)
                }
            } catch {
                // Silently ignore or delegate error log
            }
            return nil
        }
        
        activeTasks[cacheKey] = task
        let result = await task.value
        activeTasks[cacheKey] = nil
        return result
    }
    
    nonisolated static func renderSVGToCGImage(data: Data, targetSize: CGSize?) -> CGImage? {
        guard let nsImage = NSImage(data: data) else { return nil }
        let size = targetSize ?? nsImage.size
        nsImage.size = size
        // cgImage(forProposedRect:) is thread-safe and avoids NSGraphicsContext main-thread requirement
        return nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    
    func formattedDiskCacheSize() async -> String {
        let sizeInBytes = URLCache.shared.currentDiskUsage
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(sizeInBytes))
    }
}
