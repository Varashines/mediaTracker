import Foundation

// MARK: - TMDB Base Protocol
protocol TMDBMedia: Codable {
    var id: Int { get }
    var overview: String { get }
    var poster_path: String? { get }
    var backdrop_path: String? { get }
    var genre_ids: [Int]? { get }
    var displayTitle: String { get }
    var releaseDateString: String? { get }
    var mediaType: MediaType { get }
}

extension TMDBMedia {
    var backdrop_path: String? { nil } // Default implementation
    
    func toSearchResult() -> MediaSearchResult {
        let genreList = genre_ids?.compactMap { id in
            mediaType == .movie ? TMDBGenreMap.movieGenres[id] : TMDBGenreMap.tvGenres[id]
        }.prefix(2) ?? []
        
        var languageCode: String? = nil
        if let movie = self as? TMDBMovie {
            languageCode = movie.original_language
        } else if let tv = self as? TMDBTV {
            languageCode = tv.original_language
        }

        return MediaSearchResult(
            id: String(id),
            title: displayTitle,
            overview: overview,
            posterURL: APIClient.tmdbImageURL(path: poster_path),
            releaseDate: releaseDateString,
            genres: Array(genreList),
            type: mediaType,
            originalLanguage: languageCode
        )
    }
}

struct TMDBGenericResponse<T: Codable>: Codable {
    let results: [T]
}

// MARK: - Genre Mappings
struct TMDBGenreMap {
    static let movieGenres: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime", 
        99: "Documentary", 18: "Drama", 10751: "Family", 14: "Fantasy", 36: "History", 
        27: "Horror", 10402: "Music", 9648: "Mystery", 10749: "Romance", 878: "Sci-Fi", 
        10770: "TV Movie", 53: "Thriller", 10752: "War", 37: "Western"
    ]
    static let tvGenres: [Int: String] = [
        10759: "Action & Adventure", 16: "Animation", 35: "Comedy", 80: "Crime", 
        99: "Documentary", 18: "Drama", 10751: "Family", 10762: "Kids", 9648: "Mystery", 
        10763: "News", 10764: "Reality", 10765: "Sci-Fi & Fantasy", 10766: "Soap", 
        10767: "Talk", 10768: "War & Politics", 37: "Western"
    ]
}

struct TMDBGenre: Codable { let name: String }

struct TMDBNetwork: Codable {
    let name: String
    let logo_path: String?
}

struct TMDBPerson: Codable {
    let name: String
    let profile_path: String?
}

struct TMDBPersonSearchEntry: Codable {
    let profile_path: String?
}

struct TMDBExternalIDs: Codable {
    let tvdb_id: Int?
    let imdb_id: String?
}
struct TMDBNextEpisode: Codable { let air_date: String?, episode_number: Int?, season_number: Int? }
struct TMDBSeasonBrief: Codable { let season_number: Int, name: String?, episode_count: Int, air_date: String? }
struct TMDBSeasonResponse: Codable { let episodes: [TMDBEpisodeBrief] }
struct TMDBEpisodeBrief: Codable { let episode_number: Int, name: String?, overview: String?, air_date: String?, runtime: Int? }

struct TMDBCreditsResponse: Codable {
    let cast: [TMDBMovieCastMember]
    let crew: [TMDBMovieCrewMember]?
}

struct TMDBMovieCrewMember: Codable {
    let name: String
    let job: String?
    let profile_path: String?
}

struct TMDBMovieCastMember: Codable {
    let name: String
    let character: String?
    let profile_path: String?
    let order: Int
}

struct TMDBAggregateCreditsResponse: Codable {
    let cast: [TMDBAggregateCastMember]
    let crew: [TMDBMovieCrewMember]?
}

struct TMDBAggregateCastMember: Codable {
    let name: String
    let roles: [TMDBRole]
    let profile_path: String?
    let order: Int
    let total_episode_count: Int
}

struct TMDBRole: Codable {
    let character: String?
    let episode_count: Int
}

// MARK: - Video/Trailer
struct TMDBVideoResponse: Codable {
    let results: [TMDBVideo]?
}
struct TMDBVideo: Codable {
    let key: String
    let site: String
    let type: String
    let official: Bool?
}
