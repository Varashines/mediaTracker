import Foundation

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

    func read(at url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL) {
        try? data.write(to: url, options: .atomic)
    }

    func exists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func attributes(at url: URL) -> [FileAttributeKey: Any]? {
        try? FileManager.default.attributesOfItem(atPath: url.path)
    }
}
