import Foundation
import os

#if DEBUG
private let enableDebugLogging = true
#else
private let enableDebugLogging = false
#endif

enum AppLogger {
    static let data = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vara.mediatracker", category: "Data")
    static let network = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vara.mediatracker", category: "Network")
    static let cache = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vara.mediatracker", category: "Cache")
    static let background = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vara.mediatracker", category: "Background")
    static let ui = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vara.mediatracker", category: "UI")
    static let notifications = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vara.mediatracker", category: "Notifications")
    static let sync = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vara.mediatracker", category: "Sync")
    static let performance = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.vara.mediatracker", category: "Performance")

    static func debug(_ message: String, logger: Logger = AppLogger.data) {
        if enableDebugLogging {
            logger.debug("\(message, privacy: .public)")
        }
    }

    static func info(_ message: String, logger: Logger = AppLogger.data) {
        if enableDebugLogging {
            logger.info("\(message, privacy: .public)")
        }
    }

    static func warning(_ message: String, logger: Logger = AppLogger.data) {
        logger.warning("\(message, privacy: .public)")
    }

    static func error(_ message: String, logger: Logger = AppLogger.data) {
        logger.error("\(message, privacy: .public)")
    }
}
