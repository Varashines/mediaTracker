import Foundation

// MARK: - TVMaze Responses
struct TVMazeShowLookupResponse: Codable { let id: Int }
struct TVMazeResponse: Codable {
    let _embedded: TVMazeEmbedded?, network: TVMazeNetwork?, webChannel: TVMazeWebChannel?, schedule: TVMazeSchedule?
    var timezone: String? { network?.country?.timezone ?? webChannel?.country?.timezone }
}
struct TVMazeSchedule: Codable { let time: String?, days: [String]? }
struct TVMazeNetwork: Codable { let name: String?, country: TVMazeCountry? }
struct TVMazeWebChannel: Codable { let name: String?, country: TVMazeCountry? }
struct TVMazeCountry: Codable { let timezone: String? }
struct TVMazeEmbedded: Codable { let nextepisode: TVMazeEpisode? }
struct TVMazeEpisode: Codable { let season: Int?, number: Int?, name: String?, airdate: String, airtime: String, airstamp: String? }
