import Foundation
import SwiftData

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
        let expectedEntries = Set(items.flatMap(Self.entries(for:)))
        let existingIDs = Set(existingEntries.map(\.id))

        var removedEntries = 0
        for entry in existingEntries where !expectedEntries.contains(entry.id) {
            modelContext.delete(entry)
            removedEntries += 1
        }

        var insertedEntries = 0
        for entryID in expectedEntries where !existingIDs.contains(entryID) {
            guard let entry = Self.entry(from: entryID) else { continue }
            modelContext.insert(entry)
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

    private static func entries(for item: MediaItem) -> [String] {
        let genreKeys = normalizedKeys(item.cachedGenres)
        let providerKeys = normalizedKeys(item.cachedWatchProviders)
        let networkKeys = normalizedKeys(item.cachedNetwork?.commaSeparatedValues ?? [])

        return genreKeys.map { entryID(mediaItemID: item.id, kind: .genre, key: $0) }
            + providerKeys.map { entryID(mediaItemID: item.id, kind: .provider, key: $0) }
            + networkKeys.map { entryID(mediaItemID: item.id, kind: .network, key: $0) }
    }

    private static func normalizedKeys(_ values: [String]) -> Set<String> {
        Set(values.compactMap { value in
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return key.isEmpty ? nil : key
        })
    }

    private static func entryID(mediaItemID: String, kind: MediaFacetKind, key: String) -> String {
        "\(mediaItemID)|\(kind.rawValue)|\(key)"
    }

    private static func entry(from id: String) -> MediaFacetIndex? {
        let components = id.split(separator: "|", maxSplits: 2).map(String.init)
        guard components.count == 3,
              let kind = MediaFacetKind(rawValue: components[1]) else {
            return nil
        }
        return MediaFacetIndex(
            mediaItemID: components[0],
            kind: kind,
            key: components[2]
        )
    }
}
