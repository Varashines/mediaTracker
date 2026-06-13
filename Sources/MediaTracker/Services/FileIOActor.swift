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
}
