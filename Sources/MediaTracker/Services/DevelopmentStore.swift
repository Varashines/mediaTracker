import Foundation
import SwiftData

enum DevelopmentStore {
    static let bundleIdentifier = "com.vara.mediatracker.dev"
    static let directoryName = "MediaTracker Dev"
    static let storeFilename = "default.store"

    static var isActive: Bool {
        Bundle.main.bundleIdentifier == bundleIdentifier
    }

    static func makeConfiguration(schema: Schema) throws -> ModelConfiguration {
        guard isActive else {
            return ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                groupContainer: .none
            )
        }

        let applicationSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let storeDirectory = applicationSupportDirectory.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )

        return ModelConfiguration(
            schema: schema,
            url: storeDirectory.appendingPathComponent(storeFilename)
        )
    }
}
