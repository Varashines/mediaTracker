import Foundation

// MARK: - TVMaze Responses
struct TVMazeShowLookupResponse: Codable { let id: Int }
struct TVMazeResponse: Codable {
    let _embedded: TVMazeEmbedded?, network: TVMazeNetwork?, webChannel: TVMazeWebChannel?, schedule: TVMazeSchedule?
    let genres: [String]?
    let type: String?
    var timezone: String? { network?.country?.timezone ?? webChannel?.country?.timezone }
}

// MARK: - TVMaze Search
struct TVMazeSearchResult: Codable {
    let score: Double
    let show: TVMazeSearchShow
}
struct TVMazeSearchShow: Codable {
    let id: Int
    let name: String
}
struct TVMazeSchedule: Codable { let time: String?, days: [String]? }
struct TVMazeNetwork: Codable { let name: String?, country: TVMazeCountry? }
struct TVMazeWebChannel: Codable { let name: String?, country: TVMazeCountry? }
struct TVMazeCountry: Codable { let timezone: String? }
struct TVMazeEmbedded: Codable { let nextepisode: TVMazeEpisode? }
struct TVMazeEpisode: Codable { let season: Int?, number: Int?, name: String?, airdate: String, airtime: String, airstamp: String?, summary: String?, runtime: Int? }

extension TVMazeEpisode {
    /// Summary with HTML tags stripped and surrounding whitespace trimmed.
    var strippedSummary: String? {
        summary?
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Episodes grouped by season (> 0 only), each season sorted by episode number.
    static func rawBySeason(_ episodes: [TVMazeEpisode]) -> [Int: [TVMazeEpisode]] {
        var d: [Int: [TVMazeEpisode]] = [:]
        for ep in episodes { if let s = ep.season, s > 0 { d[s, default: []].append(ep) } }
        for (k, v) in d { d[k] = v.sorted { ($0.number ?? 0) < ($1.number ?? 0) } }
        return d
    }
}
