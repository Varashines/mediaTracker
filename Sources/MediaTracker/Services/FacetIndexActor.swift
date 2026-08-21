import Foundation
import SwiftData

private struct FacetIndexEntry: Hashable, Sendable {
    let mediaItemID: String
    let kind: MediaFacetKind
    let key: String

    var id: String {
        "\(mediaItemID)|\(kind.rawValue)|\(key)"
    }

    static func entries(for item: MediaItem) -> Set<FacetIndexEntry> {
        let genreKeys = normalizedKeys(item.cachedGenres)
        let providerKeys = normalizedKeys(item.cachedWatchProviders)
        let networkKeys = normalizedKeys(item.cachedNetwork?.commaSeparatedValues ?? [])

        return Set(
            genreKeys.map { FacetIndexEntry(mediaItemID: item.id, kind: .genre, key: $0) }
                + providerKeys.map { FacetIndexEntry(mediaItemID: item.id, kind: .provider, key: $0) }
                + networkKeys.map { FacetIndexEntry(mediaItemID: item.id, kind: .network, key: $0) }
        )
    }

    private static func normalizedKeys(_ values: [String]) -> Set<String> {
        Set(values.compactMap { value in
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return key.isEmpty ? nil : key
        })
    }
}

enum FacetIndexMaintenance {
    static func synchronize(item: MediaItem, in context: ModelContext) {
        let itemID = item.id
        let descriptor = FetchDescriptor<MediaFacetIndex>(
            predicate: #Predicate { $0.mediaItemID == itemID }
        )
        guard let existingEntries = try? context.fetch(descriptor) else {
            return
        }

        let expectedEntries = FacetIndexEntry.entries(for: item)
        let expectedIDs = Set(expectedEntries.map(\.id))
        let existingIDs = Set(existingEntries.map(\.id))

        for entry in existingEntries where !expectedIDs.contains(entry.id) {
            context.delete(entry)
        }
        for entry in expectedEntries where !existingIDs.contains(entry.id) {
            context.insert(
                MediaFacetIndex(
                    mediaItemID: entry.mediaItemID,
                    kind: entry.kind,
                    key: entry.key
                )
            )
        }
    }
}

struct FacetIndexRebuildResult: Sendable, Equatable {
    let indexedItems: Int
    let insertedEntries: Int
    let removedEntries: Int
    let unchanged: Bool
}

@ModelActor
actor FacetIndexActor {
    private static let schemaVersion = 1
    private static let schemaVersionKey = "com.vara.mediatracker.facetIndexVersion"

    nonisolated static func shared(modelContainer: ModelContainer) -> FacetIndexActor {
        FacetIndexActor(modelContainer: modelContainer)
    }

    func rebuildIfNeeded() throws -> FacetIndexRebuildResult {
        let storedVersion = UserDefaults.standard.integer(forKey: Self.schemaVersionKey)
        if storedVersion >= Self.schemaVersion {
            return FacetIndexRebuildResult(
                indexedItems: 0,
                insertedEntries: 0,
                removedEntries: 0,
                unchanged: true
            )
        }

        return try rebuild()
    }

    func rebuild() throws -> FacetIndexRebuildResult {
        var itemDescriptor = FetchDescriptor<MediaItem>()
        itemDescriptor.propertiesToFetch = [
            \.id,
            \.cachedGenres,
            \.cachedNetwork,
            \.cachedWatchProviders
        ]
        let items = try modelContext.fetch(itemDescriptor)

        let existingEntries = try modelContext.fetch(FetchDescriptor<MediaFacetIndex>())
        let expectedEntries = Set(items.flatMap { FacetIndexEntry.entries(for: $0) })
        let expectedIDs = Set(expectedEntries.map(\.id))
        let existingIDs = Set(existingEntries.map(\.id))

        var removedEntries = 0
        for entry in existingEntries where !expectedIDs.contains(entry.id) {
            modelContext.delete(entry)
            removedEntries += 1
        }

        var insertedEntries = 0
        for entry in expectedEntries where !existingIDs.contains(entry.id) {
            modelContext.insert(
                MediaFacetIndex(
                    mediaItemID: entry.mediaItemID,
                    kind: entry.kind,
                    key: entry.key
                )
            )
            insertedEntries += 1
        }

        if insertedEntries > 0 || removedEntries > 0 {
            try modelContext.save()
        }
        UserDefaults.standard.set(Self.schemaVersion, forKey: Self.schemaVersionKey)

        AppLogger.info(
            "Facet index rebuilt: items=\(items.count), inserted=\(insertedEntries), removed=\(removedEntries)",
            logger: AppLogger.data
        )
        return FacetIndexRebuildResult(
            indexedItems: items.count,
            insertedEntries: insertedEntries,
            removedEntries: removedEntries,
            unchanged: false
        )
    }
}
