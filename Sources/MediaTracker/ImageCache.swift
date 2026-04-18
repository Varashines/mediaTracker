import SwiftUI
import CryptoKit

struct ImageContainer: @unchecked Sendable {
    let image: NSImage
}

@MainActor
class ImageCache {
    static let shared = ImageCache()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let memoryCache = NSCache<NSString, NSImage>()
    private let maxDiskCacheSize: Int64 = 100 * 1024 * 1024 // 100MB
    
    private init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let basePath = paths.first ?? fileManager.temporaryDirectory
        let cacheDir = basePath.appendingPathComponent("mediatracker_images")
        self.cacheDirectory = cacheDir
        
        if !fileManager.fileExists(atPath: cacheDir.path) {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        
        memoryCache.countLimit = 50
        
        Task.detached(priority: .background) {
            await ImageCache.shared.pruneDiskCacheIfNeeded()
        }
    }
    
    func checkMemoryCache(forKey key: String, targetSize: CGSize? = nil) -> ImageContainer? {
        let cacheKey = targetSize != nil ? "\(key)_\(Int(targetSize!.width))x\(Int(targetSize!.height))" : key
        if let image = memoryCache.object(forKey: cacheKey as NSString) {
            return ImageContainer(image: image)
        }
        return nil
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
    
    func get(forKey key: String, targetSize: CGSize? = nil) async -> ImageContainer? {
        // 1. Check Memory Cache (Sync on MainActor)
        if let container = checkMemoryCache(forKey: key, targetSize: targetSize) {
            return container
        }
        
        // 2. Check Disk Cache (Off-Main-Thread via Task.detached)
        let diskFileName = fileName(for: key, size: targetSize)
        let fileURL = cacheDirectory.appendingPathComponent(diskFileName)
        
        let container = await Task.detached(priority: .userInitiated) { () -> ImageContainer? in
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            
            // Efficient decoding off-main
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
            return ImageContainer(image: nsImage)
        }.value
        
        if let nsImage = container?.image {
            let cacheKey = targetSize != nil ? "\(key)_\(Int(targetSize!.width))x\(Int(targetSize!.height))" : key
            self.memoryCache.setObject(nsImage, forKey: cacheKey as NSString)
            return ImageContainer(image: nsImage)
        }
        
        return nil
    }
    
    func save(image: NSImage, data: Data? = nil, forKey key: String, targetSize: CGSize? = nil) async {
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
        let diskFileName = fileName(for: key, size: targetSize)
        let diskCacheDir = cacheDirectory

        let rawData = data
        let isResizing = targetSize != nil && image.size != targetSize
        let container = ImageContainer(image: finalImage)
        
        Task.detached(priority: .background) {
            let fileURL = diskCacheDir.appendingPathComponent(diskFileName)
            
            if let data = rawData, !isResizing {
                try? data.write(to: fileURL)
            } else {
                guard let tiffData = container.image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData) else { return }
                
                let dataToWrite: Data?
                if bitmap.hasAlpha {
                    dataToWrite = bitmap.representation(using: .png, properties: [:])
                } else {
                    dataToWrite = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
                }
                try? dataToWrite?.write(to: fileURL)
            }
        }
    }
    
    private func downsample(image: NSImage, to size: CGSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: image.size),
                  operation: .sourceOver,
                  fraction: 1.0)
        newImage.unlockFocus()
        return newImage
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
                    if let url = url {
                        let key = url.absoluteString
                        if let container = ImageCache.shared.checkMemoryCache(forKey: key, targetSize: targetSize) {
                            self.image = container.image
                            return
                        }
                    }
                    await loadImage()
                }
            }
        }
    }
    
    private func loadImage() async {
        guard let url = url, !isLoading else { return }
        let key = url.absoluteString
        
        // 1. Check Memory/Disk
        if let container = await ImageCache.shared.get(forKey: key, targetSize: targetSize) {
            self.image = container.image
            onImageLoaded?(container.image)
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
            
            await ImageCache.shared.save(image: downloadedImage, data: data, forKey: key, targetSize: targetSize)
            if let container = await ImageCache.shared.get(forKey: key, targetSize: targetSize) {
                self.image = container.image
                onImageLoaded?(container.image)
            }
            isLoading = false
        } catch {
            isLoading = false
        }
    }
}
