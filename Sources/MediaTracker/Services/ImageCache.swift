import SwiftUI
import UniformTypeIdentifiers
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
    
    nonisolated var imageSession: URLSession { .shared }
    
    private let memoryCache = NSCache<NSString, CachedImageWrapper>()
    private var activeTasks: [String: Task<ImageContainer?, Never>] = [:]
    private let maxConcurrentLoads = 6
    private let currentLoads = OSAllocatedUnfairLock<Int>(uncheckedState: 0)
    
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    private override init() {
        super.init()
        memoryCache.delegate = self
        memoryCache.countLimit = 250
        memoryCache.totalCostLimit = 128 * 1024 * 1024 // 128MB

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
    
    func get(forKey key: String, targetSize: CGSize? = nil, priority: ImagePriority = .normal, alwaysPreserveAlpha: Bool = false) async -> ImageContainer? {
        let cacheKey = generateCacheKey(key: key, size: targetSize)
        
        if let cached = checkMemoryCache(forKey: key, targetSize: targetSize) {
            return cached
        }
        
        if let active = activeTasks[cacheKey] {
            return await active.value
        }
        
        // Throttle concurrent loads to prevent bursts on cold start
        if currentLoads.withLock({ $0 }) >= maxConcurrentLoads {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms backoff
        }
        currentLoads.withLock { $0 += 1 }
        
        let task = Task<ImageContainer?, Never> { [weak self] in
            defer {
                self?.currentLoads.withLock { $0 -= 1 }
            }
            guard let self = self else { return nil }
            guard let url = URL(string: key) else { return nil }
            
            do {
                let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 15.0)
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if Task.isCancelled { return nil }
                
                // Decode off the main actor to avoid blocking UI
                let finalCGImage: CGImage? = await Task.detached(priority: .utility) {
                    if key.lowercased().hasSuffix(".svg") || (response.mimeType?.contains("svg") ?? false) {
                        // Render SVG off-main using CGContext (avoids MainActor hop for NSGraphicsContext)
                        return Self.renderSVGToCGImage(data: data, targetSize: targetSize)
                    } else if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                        if let target = targetSize {
                            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
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
                
                if Task.isCancelled { return nil }
                
                if let cgImage = finalCGImage {
                    let container = ImageContainer(image: cgImage)
                    let wrapper = CachedImageWrapper(image: cgImage, urlString: key, cacheKey: cacheKey)
                    self.memoryCache.setObject(wrapper, forKey: cacheKey as NSString, cost: cgImage.bytesPerRow * cgImage.height)
                    return container
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
