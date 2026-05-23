import Foundation
import OSLog

@MainActor
class MemoryPressureMonitor {
    static let shared = MemoryPressureMonitor()
    private let logger = Logger(subsystem: "com.mediatracker", category: "MemoryPressure")
    
    private var source: DispatchSourceMemoryPressure?
    
    private init() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        
        source.setEventHandler { [weak self] in
            let event = source.data
            self?.handleMemoryPressure(event: event)
        }
        
        source.resume()
        self.source = source
    }
    
    private func handleMemoryPressure(event: DispatchSource.MemoryPressureEvent) {
        switch event {
        case .warning:
            logger.warning("Memory pressure warning. Reducing cache sizes.")
            ImageCache.shared.performMemoryCompaction(level: .warning)
            Task { await APIClient.shared.clearMemoryCaches() }
        case .critical:
            logger.error("Critical memory pressure! Purging all non-essential memory.")
            ImageCache.shared.performMemoryCompaction(level: .critical)
            Task { await APIClient.shared.clearMemoryCaches() }
        default:
            break
        }
    }
}
