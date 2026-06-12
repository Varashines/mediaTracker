import CoreSpotlight
import SwiftData

@MainActor
final class SpotlightIndexService {
    static let shared = SpotlightIndexService()

    private let index = CSSearchableIndex.default()
    private let posterCache = PosterCacheService.shared
    private var isIndexing = false

    nonisolated(unsafe) static var modelContainer: ModelContainer?

    private init() {}

    func indexItem(_ item: MediaItem) async {
        let attributeSet = await buildAttributeSet(for: item)
        let domainID = item.type == .movie ? "movie" : "tvShow"
        let searchableItem = CSSearchableItem(
            uniqueIdentifier: item.id,
            domainIdentifier: domainID,
            attributeSet: attributeSet
        )
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                index.indexSearchableItems([searchableItem]) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            AppLogger.error("Spotlight: failed to index \(item.id): \(error)")
        }
    }

    func deleteItem(identifier: String) async {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                index.deleteSearchableItems(withIdentifiers: [identifier]) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            AppLogger.error("Spotlight: failed to delete \(identifier): \(error)")
        }
    }

    func deleteAllItems() async {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                index.deleteAllSearchableItems { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            AppLogger.error("Spotlight: failed to delete all: \(error)")
        }
    }

    func reindexAll(_ items: [MediaItem]) async {
        guard !isIndexing else { return }
        isIndexing = true
        defer { isIndexing = false }

        let batchSize = 50
        for startIndex in stride(from: 0, to: items.count, by: batchSize) {
            let endIndex = min(startIndex + batchSize, items.count)
            let batch = items[startIndex..<endIndex]

            var searchableItems: [CSSearchableItem] = []
            for item in batch {
                let attributeSet = await buildAttributeSet(for: item)
                let domainID = item.type == .movie ? "movie" : "tvShow"
                let searchableItem = CSSearchableItem(
                    uniqueIdentifier: item.id,
                    domainIdentifier: domainID,
                    attributeSet: attributeSet
                )
                searchableItems.append(searchableItem)
            }

            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    index.indexSearchableItems(searchableItems) { error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            } catch {
                AppLogger.error("Spotlight: batch indexing error: \(error)")
            }
        }
    }

    private func buildAttributeSet(for item: MediaItem) async -> CSSearchableItemAttributeSet {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .content)

        attributeSet.title = item.title
        attributeSet.contentDescription = item.overview

        var keywords = [String]()
        keywords.append(item.title)
        keywords.append(contentsOf: item.cachedGenres)
        keywords.append(contentsOf: item.cachedCreators)
        if let network = item.cachedNetwork { keywords.append(network) }
        if let language = item.cachedLanguage { keywords.append(language) }
        attributeSet.keywords = keywords

        if let posterURL = item.posterURL, let fileURL = await posterCache.ensurePosterCached(posterURL: posterURL) {
            attributeSet.thumbnailURL = fileURL
        }

        attributeSet.contentCreationDate = item.dateAdded
        attributeSet.metadataModificationDate = item.lastUpdated
        if let releaseDate = item.releaseDate {
            attributeSet.dueDate = releaseDate
        }

        attributeSet.contentType = item.type == .movie ? "Movie" : "TV Show"

        return attributeSet
    }
}
