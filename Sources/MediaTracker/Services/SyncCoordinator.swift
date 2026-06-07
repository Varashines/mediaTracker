import Foundation

/// Global coordinator to prevent duplicate asynchronous tasks for the same resource.
actor SyncCoordinator {
    static let shared = SyncCoordinator()
    private var inFlightTasks: [String: Task<Sendable, Error>] = [:]
    private var refCounts: [String: Int] = [:]

    /// Performs a synchronized operation for a given key.
    /// If an operation for the same key is already in flight, it waits for and returns the result of that task.
    func perform<T: Sendable>(key: String, operation: @Sendable @escaping () async throws -> T) async throws -> T {
        let task: Task<Sendable, Error>

        if let existingTask = inFlightTasks[key] {
            task = existingTask
        } else {
            task = Task {
                try await operation() as Sendable
            }
            inFlightTasks[key] = task
        }

        refCounts[key, default: 0] += 1

        defer {
            refCounts[key, default: 1] -= 1
            if refCounts[key] == 0 {
                inFlightTasks[key] = nil
                refCounts[key] = nil
            }
        }

        let result = try await task.value
        guard let castedResult = result as? T else {
            throw NSError(domain: "SyncCoordinator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Type mismatch for key: \(key)"])
        }
        return castedResult
    }
}
