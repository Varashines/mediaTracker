import Foundation
import SwiftData

enum WatchEventSource: String, Codable, Sendable {
    case manual
    case automatic
    case imported
    case migration
}

@Model
final class WatchEvent {
    #Index<WatchEvent>([\.mediaID, \.cycleID, \.watchedAt])

    @Attribute(.unique) var id: UUID
    var cycleID: UUID
    var mediaID: String
    var episodeID: String?
    var watchedAt: Date
    var sourceRaw: String
    var timezoneIdentifier: String?
    var runtimeMinutes: Int?
    var voidedAt: Date?
    var deduplicationKey: String
    var isBackfilled: Bool

    init(
        id: UUID = UUID(),
        cycleID: UUID,
        mediaID: String,
        episodeID: String? = nil,
        watchedAt: Date = Date(),
        source: WatchEventSource = .manual,
        timezoneIdentifier: String? = TimeZone.current.identifier,
        runtimeMinutes: Int? = nil,
        voidedAt: Date? = nil,
        deduplicationKey: String,
        isBackfilled: Bool = false
    ) {
        self.id = id
        self.cycleID = cycleID
        self.mediaID = mediaID
        self.episodeID = episodeID
        self.watchedAt = watchedAt
        self.sourceRaw = source.rawValue
        self.timezoneIdentifier = timezoneIdentifier
        self.runtimeMinutes = runtimeMinutes
        self.voidedAt = voidedAt
        self.deduplicationKey = deduplicationKey
        self.isBackfilled = isBackfilled
    }

    var source: WatchEventSource {
        get { WatchEventSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var isActive: Bool {
        voidedAt == nil
    }
}
