import SwiftUI
import CryptoKit

class ImageCache {
    static let shared = ImageCache()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let memoryCache = NSCache<NSString, NSImage>()

    private init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let basePath = paths.first ?? fileManager.temporaryDirectory
        cacheDirectory = basePath.appendingPathComponent("mediatracker_images")

        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        // Limit memory cache to ~100 images to be safe
        memoryCache.countLimit = 100
    }

    private func fileName(for key: String) -> String {
        let inputData = Data(key.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    func get(forKey key: String) -> NSImage? {
        // 1. Check Memory Cache (Fastest)
        if let cachedImage = memoryCache.object(forKey: key as NSString) {
            return cachedImage
        }

        // 2. Check Disk Cache
        let fileURL = cacheDirectory.appendingPathComponent(fileName(for: key))
        guard let data = try? Data(contentsOf: fileURL), let image = NSImage(data: data) else { return nil }

        // 3. Populate Memory Cache for next time
        memoryCache.setObject(image, forKey: key as NSString)
        return image
    }

    func save(image: NSImage, forKey key: String) {
        // Save to Memory
        memoryCache.setObject(image, forKey: key as NSString)

        // Save to Disk (Asynchronously to avoid blocking UI)
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            let fileURL = self.cacheDirectory.appendingPathComponent(self.fileName(for: key))
            if let data = image.tiffRepresentation {
                let bitmap = NSBitmapImageRep(data: data)
                let jpegData = bitmap?.representation(using: .jpeg, properties: [:])
                try? jpegData?.write(to: fileURL)
            }
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
    @ViewBuilder let placeholder: Placeholder
    
    @State private var image: NSImage?
    @State private var isLoading = false
    
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
        
        // 1. Check Memory/State
        if image != nil { return }
        
        // 2. Check Disk
        if let cached = ImageCache.shared.get(forKey: key) {
            self.image = cached
            return
        }
        
        // 3. Download
        isLoading = true
        URLSession.shared.dataTask(with: url) { data, response, error in
            defer { isLoading = false }
            guard let data = data, let downloadedImage = NSImage(data: data) else { return }
            
            ImageCache.shared.save(image: downloadedImage, forKey: key)
            
            DispatchQueue.main.async {
                self.image = downloadedImage
            }
        }.resume()
    }
}
