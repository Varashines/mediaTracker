import Foundation
import SwiftData

struct SearchTextBackfillResult: Sendable, Equatable {
    let updatedItems: Int
    let unchanged: Bool
}

@ModelActor
actor SearchTextBackfillActor {
    private static let schemaVersion = 1
    private static let schemaVersionKey = "com.vara.mediatracker.searchTextBackfillVersion"

    nonisolated static func shared(modelContainer: ModelContainer) -> SearchTextBackfillActor {
        SearchTextBackfillActor(modelContainer: modelContainer)
    }

    func rebuildIfNeeded() throws -> SearchTextBackfillResult {
        let storedVersion = UserDefaults.standard.integer(forKey: Self.schemaVersionKey)
        guard storedVersion < Self.schemaVersion else {
            return SearchTextBackfillResult(updatedItems: 0, unchanged: true)
        }

        return try rebuild()
    }

    func rebuild() throws -> SearchTextBackfillResult {
        let items = try modelContext.fetch(FetchDescriptor<MediaItem>())
        var updatedItems = 0

        for item in items {
            let previousSearchableText = item.searchableText
            item.updateSearchableText()
            if item.searchableText != previousSearchableText {
                updatedItems += 1
            }
        }

        if updatedItems > 0 {
            try modelContext.save()
        }
        UserDefaults.standard.set(Self.schemaVersion, forKey: Self.schemaVersionKey)

        AppLogger.info(
            "Search text backfill completed: updated=\(updatedItems), total=\(items.count)",
            logger: AppLogger.data
        )
        return SearchTextBackfillResult(updatedItems: updatedItems, unchanged: false)
    }
}
