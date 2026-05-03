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
            NotificationCenter.default.post(name: .memoryPressureWarning, object: nil)
        case .critical:
            logger.error("Critical memory pressure! Purging all non-essential memory.")
            // Phase 3: Immediate context clearing for 8GB RAM preservation
            NotificationCenter.default.post(name: .memoryPressureCritical, object: nil)
        default:
            break
        }
    }
}

extension Notification.Name {
    static let memoryPressureWarning = Notification.Name("memoryPressureWarning")
    static let memoryPressureCritical = Notification.Name("memoryPressureCritical")
}
