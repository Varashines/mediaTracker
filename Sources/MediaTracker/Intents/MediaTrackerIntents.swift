import AppIntents
import SwiftData

struct MediaItemEntity: AppEntity, Identifiable {
    let id: String
    let title: String
    let type: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: type == "Movie" ? "Movie" : "TV Show"
        )
    }

    private static let _typeDisplay: TypeDisplayRepresentation = "Media Item"
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation { _typeDisplay }

    private static let _query = MediaItemEntityQuery()
    nonisolated static var defaultQuery: MediaItemEntityQuery { _query }
}

struct MediaItemEntityQuery: EntityQuery, Sendable {
    @MainActor
    func entities(for identifiers: [MediaItemEntity.ID]) async throws -> [MediaItemEntity] {
        guard let container = DataService.modelContainer else { return [] }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { identifiers.contains($0.id) }
        )
        descriptor.propertiesToFetch = [\.id, \.title, \.typeValue]
        let items = (try? context.fetch(descriptor)) ?? []
        return items.map { MediaItemEntity(id: $0.id, title: $0.title, type: $0.typeValue) }
    }

    @MainActor
    func suggestedEntities() async throws -> [MediaItemEntity] {
        guard let container = DataService.modelContainer else { return [] }
        let context = ModelContext(container)
        let activeRaw = MediaState.activeRaw
        var descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.stateValue == activeRaw }
        )
        descriptor.propertiesToFetch = [\.id, \.title, \.typeValue]
        descriptor.fetchLimit = 20
        let items = (try? context.fetch(descriptor)) ?? []
        return items.map { MediaItemEntity(id: $0.id, title: $0.title, type: $0.typeValue) }
    }
}

struct SearchMediaIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Media"
    static let description: LocalizedStringResource = "Search your media library in MediaTracker"
    static let openAppWhenRun = true

    @Parameter(title: "Query")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(query, forKey: "spotlight_search_query")
        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Search for \(\.$query)")
    }
}

struct OpenMediaIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Media"
    static let description: LocalizedStringResource = "Open a specific movie or TV show in MediaTracker"
    static let openAppWhenRun = true

    @Parameter(title: "Media Item")
    var mediaItem: MediaItemEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(mediaItem.id, forKey: "spotlight_open_id")
        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$mediaItem)")
    }
}

struct MarkWatchedIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark as Watched"
    static let description: LocalizedStringResource = "Mark a movie or TV show as watched in MediaTracker"
    static let openAppWhenRun = false

    @Parameter(title: "Media Item")
    var mediaItem: MediaItemEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let container = DataService.modelContainer else {
            return .result()
        }
        let context = ModelContext(container)
        let targetID = mediaItem.id
        var descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == targetID })
        descriptor.propertiesToFetch = [\.id, \.title, \.typeValue, \.stateValue]
        guard let item = try? context.fetch(descriptor).first else {
            return .result()
        }
        item.state = .completed
        item.commitChange()
        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$mediaItem) as watched")
    }
}
