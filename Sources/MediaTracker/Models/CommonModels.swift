import Foundation

// MARK: - Search Results
struct MediaSearchResult: Identifiable, Codable {
    let id: String
    let title: String
    let overview: String
    let posterURL: String?
    let releaseDate: String?
    let genres: [String]
    let type: MediaType
    let originalLanguage: String?
}

// MARK: - Client Result Wrappers
struct CastMemberResult: Codable {
    let name: String
    let character: String
    let profilePath: String?
    let order: Int
}

struct TVEpisodeResult: Codable { let episodeNumber: Int, name: String?, overview: String?, airDate: String?, runtime: Int? }

struct ProductionCompanyResult: Codable {
    let name: String
    let logoPath: String?
}

// MARK: - Watch Providers
struct WatchProviderResult: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let logoPath: String?
    let watchPageURL: String?
    var logoURL: String? { logoPath.flatMap { APIClient.tmdbImageURL(path: $0, size: "w45") } }
}

// MARK: - Blocklisted provider IDs (carrier-bundled, add-on channels, aggregators)
private let blockedProviderIDs: Set<Int> = [
    614,  // VI movies and tv
    502,  // Tata Play
    1898, // Amazon MX Player
    2100, // Amazon Prime Video with Ads
    2285, // JustWatch TV
]

func extractWatchProviders(from response: TMDBWatchProvidersResponse?, regionOverride: String? = nil) -> [WatchProviderResult] {
    guard let response, let results = response.results else { return [] }
    let region = regionOverride ?? Locale.current.region?.identifier ?? "US"
    let regionData = results[region]
    guard let regionData else { return [] }
    
    let merged = (regionData.flatrate ?? []) + (regionData.free ?? [])
    return merged
        .filter { !blockedProviderIDs.contains($0.provider_id) }
        .filter {
            let name = $0.provider_name.lowercased()
            return !name.contains("amazon channel") && !name.contains("prime video channel") && !name.contains("apple tv channel")
        }
        .reduce(into: [WatchProviderResult]()) { acc, provider in
            if !acc.contains(where: { $0.id == provider.provider_id }) {
                acc.append(WatchProviderResult(id: provider.provider_id, name: provider.provider_name, logoPath: provider.logo_path, watchPageURL: regionData.link))
            }
        }
}

struct MovieDetailsResult {
    let runtime: Int?
    let genres: [String]
    let voteAverage: Double?
    let rottenTomatoesScore: Int?
    let imdbID: String?
    let releaseDate: String?
    let backdropPath: String?
    let posterPath: String?
    let overview: String?
    let originalLanguage: String?
    let status: String?
    let cast: [CastMemberResult]
    let directors: [CastMemberResult]
    let productionCompanies: [ProductionCompanyResult]
    let trailerKey: String?
    let streamingProviders: [WatchProviderResult]
}

struct TVDetailsResult {
    let status: String
    let voteAverage: Double?
    let imdbID: String?
    let genres: [String]
    let backdropPath: String?
    let posterPath: String?
    let overview: String?
    let network: String?
    let networkLogoPath: String?
    let originalLanguage: String?
    let seasons: [TMDBSeasonBrief]
    let firstAirDate: String?
    let nextEpisodeDate: String?
    let nextEpisodeNumber: Int?
    let nextSeasonNumber: Int?
    let tvdbID: Int?
    let cast: [CastMemberResult]
    let creators: [CastMemberResult]
    let trailerKey: String?
    let streamingProviders: [WatchProviderResult]
}
