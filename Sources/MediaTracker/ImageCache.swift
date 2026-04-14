import SwiftUI
import CryptoKit

class ImageCache {
    static let shared = ImageCache()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let basePath = paths.first ?? fileManager.temporaryDirectory
        cacheDirectory = basePath.appendingPathComponent("mediatracker_images")
        
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    private func fileName(for key: String) -> String {
        let inputData = Data(key.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    func get(forKey key: String) -> NSImage? {
        let fileURL = cacheDirectory.appendingPathComponent(fileName(for: key))
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return NSImage(data: data)
    }
    
    func save(image: NSImage, forKey key: String) {
        let fileURL = cacheDirectory.appendingPathComponent(fileName(for: key))
        if let data = image.tiffRepresentation {
            let bitmap = NSBitmapImageRep(data: data)
            let jpegData = bitmap?.representation(using: .jpeg, properties: [:])
            try? jpegData?.write(to: fileURL)
        }
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
                placeholder
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
