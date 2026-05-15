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
            if Task.isCancelled { return }
            
            ImageCache.shared.prewarmImages(urls: newURLs, targetSize: targetSize, priority: .low)
            
            // Maintain a larger bounded set of recently prefetched (250 items)
            let current = Set(urls)
            if lastPrefetchedURLs.count > 250 {
                lastPrefetchedURLs = current
            } else {
                lastPrefetchedURLs.formUnion(current)
            }
        }
    }
    
    func cancel() {
        prefetchTask?.cancel()
        prefetchTask = nil
    }
}
