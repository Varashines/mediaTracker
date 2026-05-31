import SwiftUI
import Combine

@MainActor
class PrefetchManager {
    static let shared = PrefetchManager()
    
    private var prefetchTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var pendingURLs: [URL] = []
    private var pendingTargetSize: CGSize = .zero
    private var lastPrefetchedURLs: Set<URL> = []
    
    private init() {}
    
    func prefetch(urls: [URL], targetSize: CGSize) {
        pendingURLs.append(contentsOf: urls)
        pendingTargetSize = targetSize
        
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            if Task.isCancelled { return }
            let batch = pendingURLs
            pendingURLs.removeAll()
            await performPrefetch(urls: batch, targetSize: pendingTargetSize)
        }
    }
    
    private func performPrefetch(urls: [URL], targetSize: CGSize) async {
        let newURLs = urls.filter { !lastPrefetchedURLs.contains($0) }
        guard !newURLs.isEmpty else { return }
        
        prefetchTask?.cancel()
        
        prefetchTask = Task {
            if Task.isCancelled { return }
            
            let prewarmTask = ImageCache.shared.prewarmImages(urls: newURLs, targetSize: targetSize, priority: .low)
            
            await withTaskCancellationHandler {
                await prewarmTask.value
            } onCancel: {
                prewarmTask.cancel()
            }
            
            if Task.isCancelled { return }
            
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
        debounceTask?.cancel()
        debounceTask = nil
        pendingURLs.removeAll()
    }
}
