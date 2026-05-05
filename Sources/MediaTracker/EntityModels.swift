import Foundation
import SwiftData

@Model
final class NetworkEntity {
    var name: String
    var logoPath: String?
    var count: Int = 0
    var themeColorHex: String?
    var sourceNames: [String] = []

    init(name: String, logoPath: String? = nil, count: Int = 0, themeColorHex: String? = nil, sourceNames: [String] = []) {
        self.name = name
        self.logoPath = logoPath
        self.count = count
        self.themeColorHex = themeColorHex
        self.sourceNames = sourceNames
    }
}

@Model
final class GenreEntity {
    var name: String
    var count: Int = 0

    init(name: String, count: Int = 0) {
        self.name = name
        self.count = count
    }
}

@Model
final class LanguageEntity {
    var code: String
    var count: Int = 0

    init(code: String, count: Int = 0) {
        self.code = code
        self.count = count
    }
}

@Model
final class StudioAliasEntity {
    @Attribute(.unique) var target: String
    var sources: [String] = []
    var preferredLogoSource: String?

    init(target: String, sources: [String] = [], preferredLogoSource: String? = nil) {
        self.target = target
        self.sources = sources
        self.preferredLogoSource = preferredLogoSource
    }
}

@Model
final class SearchCacheEntity {
    @Attribute(.unique) var key: String // "type_query"
    var query: String
    var type: String
    var resultsData: Data
    var timestamp: Date

    init(query: String, type: String, resultsData: Data, timestamp: Date = Date()) {
        self.query = query
        self.type = type
        self.key = "\(type)_\(query)"
        self.resultsData = resultsData
        self.timestamp = timestamp
    }
}

@Model
final class PersonImageEntity {
    var name: String
    var profileURL: String?
    
    init(name: String, profileURL: String?) {
        self.name = name
        self.profileURL = profileURL
    }
}

extension Notification.Name {
    static let mediaItemRefreshed = Notification.Name("mediaItemRefreshed")
    static let mediaItemsBulkRefreshed = Notification.Name("mediaItemsBulkRefreshed")
    static let mediaStateChanged = Notification.Name("mediaStateChanged")
}
