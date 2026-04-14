import SwiftUI
import CryptoKit

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
        
        memoryCache.countLimit = 150 // Increased slightly for thumbnails
        
        // Prune on startup
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
    
    func get(forKey key: String, targetSize: CGSize? = nil) -> NSImage? {
        let cacheKey = targetSize != nil ? "\(key)_\(Int(targetSize!.width))x\(Int(targetSize!.height))" : key
        
        if let cachedImage = memoryCache.object(forKey: cacheKey as NSString) {
            return cachedImage
        }
        
        let fileURL = cacheDirectory.appendingPathComponent(fileName(for: key, size: targetSize))
        guard let data = try? Data(contentsOf: fileURL), let image = NSImage(data: data) else { return nil }
        
        memoryCache.setObject(image, forKey: cacheKey as NSString)
        return image
    }
    
    func save(image: NSImage, forKey key: String, targetSize: CGSize? = nil) {
        let cacheKey = targetSize != nil ? "\(key)_\(Int(targetSize!.width))x\(Int(targetSize!.height))" : key
        
        // Downsample if targetSize is provided
        let finalImage: NSImage
        if let size = targetSize, image.size != size {
            finalImage = downsample(image: image, to: size)
        } else {
            finalImage = image
        }

        memoryCache.setObject(finalImage, forKey: cacheKey as NSString)
        
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            let fileURL = self.cacheDirectory.appendingPathComponent(self.fileName(for: key, size: targetSize))
            if let data = finalImage.tiffRepresentation {
                let bitmap = NSBitmapImageRep(data: data)
                let jpegData = bitmap?.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                try? jpegData?.write(to: fileURL)
            }
        }
    }
    
    private func downsample(image: NSImage, to size: CGSize) -> NSImage {
        let destRect = NSRect(origin: .zero, size: size)
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(in: destRect, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
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
            // Sort by access date (oldest first)
            let sortedFiles = fileInfos.sorted(by: { $0.date < $1.date })
            var currentSize = totalSize
            
            for file in sortedFiles {
                if currentSize <= (maxDiskCacheSize * 8 / 10) { break } // Prune down to 80%
                try? fileManager.removeItem(at: file.url)
                currentSize -= file.size
            }
            print("🧹 Pruned disk cache: \(totalSize / 1024 / 1024)MB -> \(currentSize / 1024 / 1024)MB")
        }
    }
}

struct ShimmerView: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.secondary.opacity(0.1)
                
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .white.opacity(0.2), .clear]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: geometry.size.width * 2)
                .offset(x: -geometry.size.width + (geometry.size.width * 2 * phase))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .clipped()
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
                    placeholder
                    ShimmerView()
                }
                .onAppear {
                    loadImage()
                }
            }
        }
    }
    
    private func loadImage() {
        guard let url = url, !isLoading else { return }
        let key = url.absoluteString
        
        // 1. Check Memory/Disk
        if let cached = ImageCache.shared.get(forKey: key, targetSize: targetSize) {
            self.image = cached
            onImageLoaded?(cached)
            return
        }
        
        // 2. Download
        isLoading = true
        URLSession.shared.dataTask(with: url) { data, response, error in
            defer { isLoading = false }
            guard let data = data, let downloadedImage = NSImage(data: data) else { return }
            
            ImageCache.shared.save(image: downloadedImage, forKey: key, targetSize: targetSize)
            
            DispatchQueue.main.async {
                if let finalImage = ImageCache.shared.get(forKey: key, targetSize: targetSize) {
                    self.image = finalImage
                    onImageLoaded?(finalImage)
                }
            }
        }.resume()
    }
}
