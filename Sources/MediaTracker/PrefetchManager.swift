import SwiftUI
import Combine

@MainActor
class PrefetchManager {
    static let shared = PrefetchManager()
    
    private var prefetchTask: Task<Void, Never>?
    private var lastPrefetchedURLs: Set<URL> = []
    
    private init() {}
    
    func prefetch(urls: [URL], targetSize: CGSize) {
        // Filter out URLs we already prefetched recently to avoid redundant work
        let newURLs = urls.filter { !lastPrefetchedURLs.contains($0) }
        guard !newURLs.isEmpty else { return }
        
        prefetchTask?.cancel()
        
        prefetchTask = Task {
            // Give the main thread a breath
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
            
            ImageCache.shared.prewarmImages(urls: newURLs, targetSize: targetSize, priority: .low)
            
            // Maintain a small set of recently prefetched to avoid thrashing
            lastPrefetchedURLs = Set(urls)
        }
    }
    
    func cancel() {
        prefetchTask?.cancel()
        prefetchTask = nil
    }
}
