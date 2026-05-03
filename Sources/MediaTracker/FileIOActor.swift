import Foundation

/// A global actor for coordinating heavy disk I/O operations to prevent thread pool exhaustion and race conditions.
@globalActor
actor FileIOActor {
    static let shared = FileIOActor()
    private var activeCount = 0
    private let maxConcurrent = 6
    private var suspendedContinuations: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ work: @Sendable @escaping () async throws -> T) async rethrows -> T {
        if activeCount >= maxConcurrent {
            await withCheckedContinuation { continuation in
                suspendedContinuations.append(continuation)
            }
        }
        
        activeCount += 1
        defer {
            activeCount -= 1
            if let next = suspendedContinuations.first {
                suspendedContinuations.removeFirst()
                next.resume()
            }
        }
        
        return try await work()
    }
    
    /// Helper for reading data safely
    func read(at url: URL) -> Data? {
        return try? Data(contentsOf: url)
    }
    
    /// Helper for writing data safely
    func write(_ data: Data, to url: URL) {
        try? data.write(to: url, options: .atomic)
    }
    
    /// Helper for checking if a file exists
    func exists(at url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    /// Helper for getting file attributes
    func attributes(at url: URL) -> [FileAttributeKey: Any]? {
        return try? FileManager.default.attributesOfItem(atPath: url.path)
    }
}
