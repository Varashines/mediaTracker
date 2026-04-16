import SwiftUI
import CryptoKit

@MainActor
class ImageCache {
    static let shared = ImageCache()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let memoryCache = NSCache<NSString, NSImage>()
    private let maxDiskCacheSize: Int64 = 500 * 1024 * 1024 // 500MB
    
    private init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let basePath = paths.first ?? fileManager.temporaryDirectory
        cacheDirectory = basePath.appendingPathComponent("mediatracker_images")
        
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        
        memoryCache.countLimit = 150
        
        Task.detached(priority: .background) {
            await self.pruneDiskCacheIfNeeded()
        }
    }
    
    private func fileName(for key: String, size: CGSize?) -> String {
        var finalKey = key
        if let size = size {
            finalKey += "_\(Int(size.width))x\(Int(size.height))"
        }
        let inputData = Data(finalKey.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    func get(forKey key: String, targetSize: CGSize? = nil) async -> NSImage? {
        let cacheKey = targetSize != nil ? "\(key)_\(Int(targetSize!.width))x\(Int(targetSize!.height))" : key
        
        // 1. Check Memory Cache
        if let cachedImage = memoryCache.object(forKey: cacheKey as NSString) {
            return cachedImage
        }
        
        // 2. Check Disk Cache (Off-Main-Thread)
        let fileURL = cacheDirectory.appendingPathComponent(fileName(for: key, size: targetSize))
        
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            
            // Use CGImageSource for efficient, non-blocking decoding
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            
            let nsImage = NSImage(cgImage: cgImage, size: targetSize ?? NSSize(width: cgImage.width, height: cgImage.height))
            
            await MainActor.run {
                self.memoryCache.setObject(nsImage, forKey: cacheKey as NSString)
            }
            
            return nsImage
        }.value
    }
    
    func save(image: NSImage, forKey key: String, targetSize: CGSize? = nil) async {
        let cacheKey = targetSize != nil ? "\(key)_\(Int(targetSize!.width))x\(Int(targetSize!.height))" : key
        
        // 1. Memory Cache
        let finalImage: NSImage
        if let size = targetSize, image.size != size {
            finalImage = downsample(image: image, to: size)
        } else {
            finalImage = image
        }
        memoryCache.setObject(finalImage, forKey: cacheKey as NSString)
        
        // 2. Disk Cache (Background)
        guard let imageData = finalImage.tiffRepresentation else { return }
        let diskFileName = fileName(for: key, size: targetSize)
        let diskCacheDir = cacheDirectory

        Task.detached(priority: .background) {
            let fileURL = diskCacheDir.appendingPathComponent(diskFileName)
            let bitmap = NSBitmapImageRep(data: imageData)
            let jpegData = bitmap?.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
            try? jpegData?.write(to: fileURL)
        }
    }
    
    private func downsample(image: NSImage, to size: CGSize) -> NSImage {
        let sourceSize = image.size
        let widthRatio = size.width / sourceSize.width
        let heightRatio = size.height / sourceSize.height
        let ratio = max(widthRatio, heightRatio)
        
        let newWidth = size.width / ratio
        let newHeight = size.height / ratio
        
        let sourceRect = NSRect(
            x: (sourceSize.width - newWidth) / 2,
            y: (sourceSize.height - newHeight) / 2,
            width: newWidth,
            height: newHeight
        )
        
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: sourceRect, operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
    
    private func pruneDiskCacheIfNeeded() async {
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
    var onImageLoaded: ((NSImage) -> Void)? = nil
    @ViewBuilder let placeholder: Placeholder
    
    @State private var image: NSImage?
    @State private var isLoading = false
    
    init(url: URL?, targetSize: CGSize? = nil, onImageLoaded: ((NSImage) -> Void)? = nil, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.targetSize = targetSize
        self.onImageLoaded = onImageLoaded
        self.placeholder = placeholder()
    }
    
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
            } else {
                ZStack {
                    Color.secondary.opacity(0.1) // Static placeholder background
                    placeholder
                }
                .task(id: url) {
                    await loadImage()
                }
            }
        }
    }
    
    private func loadImage() async {
        guard let url = url, !isLoading else { return }
        let key = url.absoluteString
        
        // 1. Check Memory/Disk
        if let cached = await ImageCache.shared.get(forKey: key, targetSize: targetSize) {
            self.image = cached
            onImageLoaded?(cached)
            return
        }
        
        // 2. Download
        isLoading = true
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let downloadedImage = NSImage(data: data) else {
                isLoading = false
                return
            }
            
            await ImageCache.shared.save(image: downloadedImage, forKey: key, targetSize: targetSize)
            if let finalImage = await ImageCache.shared.get(forKey: key, targetSize: targetSize) {
                self.image = finalImage
                onImageLoaded?(finalImage)
            }
            isLoading = false
        } catch {
            isLoading = false
        }
    }
}
