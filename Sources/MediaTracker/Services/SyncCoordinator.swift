import Foundation

/// Global coordinator to prevent duplicate asynchronous tasks for the same resource.
actor SyncCoordinator {
    static let shared = SyncCoordinator()
    private var inFlightTasks: [String: Task<Sendable, Error>] = [:]

    /// Performs a synchronized operation for a given key. 
    /// If an operation for the same key is already in flight, it waits for and returns the result of that task.
    func perform<T: Sendable>(key: String, operation: @Sendable @escaping () async throws -> T) async throws -> T {
        if let existingTask = inFlightTasks[key] {
            guard let result = try await existingTask.value as? T else {
                // This would only happen if different types are requested for the same key
                throw NSError(domain: "SyncCoordinator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Type mismatch for key: \(key)"])
            }
            return result
        }

        let task = Task {
            try await operation() as Sendable
        }

        inFlightTasks[key] = task
        
        defer { inFlightTasks[key] = nil }
        
        let result = try await task.value
        guard let castedResult = result as? T else {
             throw NSError(domain: "SyncCoordinator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Type mismatch for key: \(key)"])
        }
        return castedResult
    }
}
