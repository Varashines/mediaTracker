import Foundation
import SwiftData

enum WatchCycleKind: String, Codable, Sendable {
    case movie
    case tvShow
}

enum WatchCycleState: String, Codable, Sendable {
    case active
    case completed
    case paused
    case archived
}

@Model
final class WatchCycle {
    #Index<WatchCycle>([\.mediaID, \.stateRaw, \.startedAt])

    @Attribute(.unique) var id: UUID
    var mediaID: String
    var kindRaw: String
    var startedAt: Date
    var completedAt: Date?
    var stateRaw: String
    var isBackfilled: Bool
    var isRewatch: Bool = false
    var isComplete: Bool = false
    var scopeEpisodeIDs: [String] = []

    init(
        id: UUID = UUID(),
        mediaID: String,
        kind: WatchCycleKind,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        state: WatchCycleState = .active,
        isBackfilled: Bool = false,
        isRewatch: Bool = false,
        isComplete: Bool = false,
        scopeEpisodeIDs: [String] = []
    ) {
        self.id = id
        self.mediaID = mediaID
        self.kindRaw = kind.rawValue
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.stateRaw = state.rawValue
        self.isBackfilled = isBackfilled
        self.isRewatch = isRewatch
        self.isComplete = isComplete
        self.scopeEpisodeIDs = scopeEpisodeIDs
    }

    var kind: WatchCycleKind {
        get { WatchCycleKind(rawValue: kindRaw) ?? .movie }
        set { kindRaw = newValue.rawValue }
    }

    var state: WatchCycleState {
        get { WatchCycleState(rawValue: stateRaw) ?? .active }
        set { stateRaw = newValue.rawValue }
    }
}
