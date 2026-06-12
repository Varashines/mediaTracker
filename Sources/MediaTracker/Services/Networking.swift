import Foundation
import UniformTypeIdentifiers

enum APIError: Error, LocalizedError {
    case missingApiKey(String)
    case invalidResponse
    case requestFailed(Int)
    case rateLimited
    
    var errorDescription: String? {
        switch self {
        case .missingApiKey(let service): return "\(service) API Key is missing. Please check Settings."
        case .invalidResponse: return "Received an invalid response from the server."
        case .requestFailed(let code): return "Request failed with status code: \(code)"
        case .rateLimited: return "Rate limit exceeded. Retrying..."
        }
    }
}

actor APIClient {
    static let shared = APIClient()
    private let decoder = JSONDecoder()
    
    // Precomputed once at init to avoid repeated synchronous filesystem checks on every cache read/write
    nonisolated let cacheFolder: URL
    
    private let apiURLCache = URLCache(
        memoryCapacity: 16 * 1024 * 1024,
        diskCapacity: 256 * 1024 * 1024,
        directory: nil
    )
    
    private(set) var session: URLSession

    // Phase 2: Search Cache (LRU-evicted, max 20 entries)
    private var inFlightTasks: [String: Task<[MediaSearchResult], Error>] = [:]
    private var searchCache: [String: [MediaSearchResult]] = [:]
    private var lastSearchTime: [String: Date] = [:]
    private let cacheExpiry: TimeInterval = 300 // 5 minutes
    private let maxSearchCacheSize = 20

    // In-flight task coalescing: prevents concurrent duplicate network requests for the same resource
    private var inFlightMovieDetails: [Int: Task<MovieDetailsResult, Error>] = [:]
    private var inFlightTVDetails: [Int: Task<TVDetailsResult, Error>] = [:]
    private var inFlightSeasonDetails: [String: Task<[TVEpisodeResult], Error>] = [:]
    
    private nonisolated var tmdbApiKey: String { UserDefaults.standard.string(forKey: UserDefaultsKeys.tmdbAPIKey.rawValue) ?? "" }
    private nonisolated var omdbApiKey: String { UserDefaults.standard.string(forKey: UserDefaultsKeys.omdbAPIKey.rawValue) ?? "" }

    // Trending cache (1-hour TTL)
    private var trendingMoviesCache: (data: [MediaSearchResult], timestamp: Date)?
    private var trendingTVCache: (data: [MediaSearchResult], timestamp: Date)?
    private let trendingCacheTTL: TimeInterval = 3600

    #if DEBUG
    init(testing session: URLSession) {
        self.session = session
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = paths.first ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("api_details_cache_test")
        self.cacheFolder = folder
    }
    #endif

    init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 15
        config.urlCache = apiURLCache
        self.session = URLSession(configuration: config)
        
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = paths.first ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("api_details_cache")
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        self.cacheFolder = folder
    }

    #if DEBUG
    func configureForTesting(session: URLSession) {
        self.session = session
    }
    #endif

    private func clearSearchCache() {
        searchCache.removeAll()
        lastSearchTime.removeAll()
    }

    private func evictOldestSearchCacheEntry() {
        guard let oldestKey = lastSearchTime.min(by: { $0.value < $1.value })?.key else { return }
        searchCache.removeValue(forKey: oldestKey)
        lastSearchTime.removeValue(forKey: oldestKey)
    }

    func clearMemoryCaches() {
        clearSearchCache()
        trendingMoviesCache = nil
        trendingTVCache = nil
        apiURLCache.removeAllCachedResponses()
    }

    nonisolated var isTMDBConfigured: Bool {
        UserDefaults.standard.string(forKey: UserDefaultsKeys.tmdbAPIKey.rawValue)?.isEmpty == false
    }
    
    private nonisolated func tmdbURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        let key = tmdbApiKey
        guard !key.isEmpty else { throw APIError.missingApiKey("TMDB") }
        
        let region = Locale.current.region?.identifier ?? "US"
        
        // Phase 5 Improvement: Robust locale construction for TMDB
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
        let language = "\(languageCode)-\(region)"
        
        var components = URLComponents(string: "https://api.themoviedb.org/3\(path)")
        var items = [
            URLQueryItem(name: "api_key", value: key),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "region", value: region)
        ]
        items.append(contentsOf: queryItems)
        components?.queryItems = items
        guard let url = components?.url else { throw URLError(.badURL) }
        return url
    }

    // MARK: - Disk Cache Helpers
    private func getCachedData(forKey key: String, ttl: TimeInterval = .days7) async -> Data? {
        let fileURL = cacheFolder.appendingPathComponent(key)

        return await FileIOActor.shared.run {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let modificationDate = attributes[.modificationDate] as? Date,
                  Date().timeIntervalSince(modificationDate) < ttl else {
                return nil
            }
            return try? Data(contentsOf: fileURL)
        }
    }

    private nonisolated func saveToCache(data: Data, forKey key: String) {
        let fileURL = cacheFolder.appendingPathComponent(key)
        Task.detached(priority: .background) {
            await FileIOActor.shared.run {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    nonisolated func removeCachedResponse(forKey key: String) {
        let fileURL = cacheFolder.appendingPathComponent(key)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Generic Search
    private func parseQueryAndYear(from text: String) -> (query: String, year: String?) {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count > 1, let lastPart = parts.last, lastPart.count == 4, Int(lastPart) != nil {
            let query = parts.dropLast().joined(separator: ", ")
            return (query, lastPart)
        }
        return (text, nil)
    }

    private func searchTMDB<T: Codable & TMDBMedia & Sendable>(path: String, query: String, year: String? = nil) async throws -> [T] {
        return try await executeWithRetry {
            var queryItems = [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "include_adult", value: "false")
            ]
            
            if let year = year {
                // TMDB uses different keys for year based on search type
                let yearKey = path.contains("movie") ? "primary_release_year" : "first_air_date_year"
                queryItems.append(URLQueryItem(name: yearKey, value: year))
            }
            
            let url = try self.tmdbURL(path: path, queryItems: queryItems)
            let (data, response) = try await self.session.data(from: url)
            try self.validateResponse(response)
            let decoded = try self.decoder.decode(TMDBGenericResponse<T>.self, from: data)
            return decoded.results
        }
    }

    func searchMovies(query: String) async throws -> [MediaSearchResult] {
        let (cleanQuery, year) = parseQueryAndYear(from: query)
        let cacheKey = "search_movie_\(query)" // Use raw query for unique cache per year filter
        
        if let date = lastSearchTime[cacheKey], Date().timeIntervalSince(date) < cacheExpiry {
            return searchCache[cacheKey] ?? []
        }

        if let inFlight = inFlightTasks[cacheKey] {
            return try await inFlight.value
        }

        let task = Task {
            // Phase 3: Disk Cache check for searches
            if let cachedData = await getCachedData(forKey: "\(cacheKey).json"),
               let results = try? decoder.decode([MediaSearchResult].self, from: cachedData) {
                return results
            }
            
            let results: [TMDBMovie] = try await searchTMDB(path: "/search/movie", query: cleanQuery, year: year)
            let final = results.map { $0.toSearchResult() }
            
            if let encoded = try? JSONEncoder().encode(final) {
                saveToCache(data: encoded, forKey: "\(cacheKey).json")
            }
            return final
        }

        inFlightTasks[cacheKey] = task
        
        do {
            let results = try await task.value
            inFlightTasks[cacheKey] = nil
            if searchCache.count >= maxSearchCacheSize {
                evictOldestSearchCacheEntry()
            }
            searchCache[cacheKey] = results
            lastSearchTime[cacheKey] = Date()
            return results
        } catch {
            inFlightTasks[cacheKey] = nil
            throw error
        }
    }
    
    func searchTVShows(query: String) async throws -> [MediaSearchResult] {
        let (cleanQuery, year) = parseQueryAndYear(from: query)
        let cacheKey = "search_tv_\(query)" // Use raw query for unique cache per year filter
        
        if let date = lastSearchTime[cacheKey], Date().timeIntervalSince(date) < cacheExpiry {
            return searchCache[cacheKey] ?? []
        }

        if let inFlight = inFlightTasks[cacheKey] {
            return try await inFlight.value
        }

        let task = Task {
            // Phase 3: Disk Cache check for searches
            if let cachedData = await getCachedData(forKey: "\(cacheKey).json"),
               let results = try? decoder.decode([MediaSearchResult].self, from: cachedData) {
                return results
            }

            let results: [TMDBTV] = try await searchTMDB(path: "/search/tv", query: cleanQuery, year: year)
            let final = results.map { $0.toSearchResult() }
            
            if let encoded = try? JSONEncoder().encode(final) {
                saveToCache(data: encoded, forKey: "\(cacheKey).json")
            }
            return final
        }

        inFlightTasks[cacheKey] = task

        do {
            let results = try await task.value
            inFlightTasks[cacheKey] = nil
            if searchCache.count >= maxSearchCacheSize {
                evictOldestSearchCacheEntry()
            }
            searchCache[cacheKey] = results
            lastSearchTime[cacheKey] = Date()
            return results
        } catch {
            inFlightTasks[cacheKey] = nil
            throw error
        }
    }
    
    // MARK: - Details

    func fetchMovieDetails(tmdbID: Int, force: Bool = false) async throws -> MovieDetailsResult {
        let cacheKey = "movie_details_\(tmdbID).json"
        if !force,
           let cachedData = await getCachedData(forKey: cacheKey, ttl: 7 * .secondsInDay),
           let details = try? decoder.decode(TMDBMovieDetailsResponse.self, from: cachedData) {
            return processMovieDetails(details)
        }

        if let existing = inFlightMovieDetails[tmdbID] {
            return try await existing.value
        }
        let task = Task<MovieDetailsResult, Error> {
            defer { self.inFlightMovieDetails.removeValue(forKey: tmdbID) }
            return try await self.executeWithRetry {
                let appendParts = force ? "credits,release_dates,external_ids,videos" : "credits,external_ids,videos"
                let url = try self.tmdbURL(path: "/movie/\(tmdbID)", queryItems: [URLQueryItem(name: "append_to_response", value: appendParts)])
                let (data, response) = try await self.session.data(from: url)
                try self.validateResponse(response)
                self.saveToCache(data: data, forKey: cacheKey)
                let details = try self.decoder.decode(TMDBMovieDetailsResponse.self, from: data)
                return self.processMovieDetails(details)
            }
        }
        inFlightMovieDetails[tmdbID] = task
        return try await task.value
    }

    private nonisolated func processMovieDetails(_ details: TMDBMovieDetailsResponse) -> MovieDetailsResult {
        let cast = details.credits?.cast.prefix(15).map { 
            CastMemberResult(name: $0.name, character: $0.character ?? "Unknown", profilePath: $0.profile_path, order: $0.order)
        } ?? []
        
        let directors = details.credits?.crew?.filter { $0.job == "Director" }.map { 
            CastMemberResult(name: $0.name, character: "Director", profilePath: $0.profile_path, order: -1)
        } ?? []
        
        // Phase 3: Dynamic release date prioritization
        var finalReleaseDate = details.release_date
        let region = Locale.current.region?.identifier ?? "US"
        
        if let releaseDates = details.release_dates?.results {
            if let local = releaseDates.first(where: { $0.iso_3166_1 == region }),
               let localDate = local.release_dates.first {
                finalReleaseDate = localDate.release_date.prefix(10).description
            } else if let us = releaseDates.first(where: { $0.iso_3166_1 == "US" }),
                    let theatrical = us.release_dates.first(where: { $0.type == 3 }) {
                finalReleaseDate = theatrical.release_date.prefix(10).description
            }
        }
        
        let productionCompanies = details.production_companies?.map {
            ProductionCompanyResult(name: $0.name, logoPath: $0.logo_path)
        } ?? []
        
        let imdbID = details.external_ids?.imdb_id
        let trailerKey = Self.extractTrailerKey(from: details.videos)

        return MovieDetailsResult(
            runtime: details.runtime, 
            genres: details.genres.map { $0.name }, 
            voteAverage: details.vote_average, 
            rottenTomatoesScore: nil,
            imdbID: imdbID,
            releaseDate: finalReleaseDate, 
            backdropPath: details.backdrop_path, 
            posterPath: details.poster_path, 
            overview: details.overview,
            originalLanguage: details.original_language, 
            cast: Array(cast), 
            directors: directors,
            productionCompanies: productionCompanies,
            trailerKey: trailerKey
        )
    }

    private static func extractTrailerKey(from videoResponse: TMDBVideoResponse?) -> String? {
        guard let videos = videoResponse?.results else {
            AppLogger.debug("🎬 No video response", logger: AppLogger.network)
            return nil
        }
        AppLogger.debug("🎬 Found \(videos.count) videos: \(videos.map { "\($0.type)|\($0.site)|\($0.official ?? false)" })", logger: AppLogger.network)
        let trailer = videos.first { $0.site == "YouTube" && $0.type == "Trailer" && $0.official == true }
            ?? videos.first { $0.site == "YouTube" && $0.type == "Trailer" }
            ?? videos.first { $0.site == "YouTube" && $0.type == "Teaser" && $0.official == true }
            ?? videos.first { $0.site == "YouTube" && $0.type == "Teaser" }
            ?? videos.first { $0.site == "YouTube" }
        AppLogger.debug("🎬 Selected trailer: \(trailer?.key ?? "none")", logger: AppLogger.network)
        return trailer?.key
    }

    func fetchTVDetails(tmdbID: Int, force: Bool = false) async throws -> TVDetailsResult {
        let cacheKey = "tv_details_\(tmdbID).json"
        if !force,
           let cachedData = await getCachedData(forKey: cacheKey, ttl: 7 * .secondsInDay),
           let d = try? decoder.decode(TMDBTVDetailsResponse.self, from: cachedData) {
            return processTVDetails(d)
        }

        // Coalesce concurrent in-flight requests for the same show to share one network call
        if let existing = inFlightTVDetails[tmdbID] {
            return try await existing.value
        }
        let task = Task<TVDetailsResult, Error> {
            defer { self.inFlightTVDetails.removeValue(forKey: tmdbID) }
            return try await self.executeWithRetry {
                let url = try self.tmdbURL(path: "/tv/\(tmdbID)", queryItems: [URLQueryItem(name: "append_to_response", value: "external_ids,aggregate_credits,videos")])
                let (data, response) = try await self.session.data(from: url)
                try self.validateResponse(response)
                self.saveToCache(data: data, forKey: cacheKey)
                let d = try self.decoder.decode(TMDBTVDetailsResponse.self, from: data)
                return self.processTVDetails(d)
            }
        }
        inFlightTVDetails[tmdbID] = task
        return try await task.value
    }

    private nonisolated func processTVDetails(_ d: TMDBTVDetailsResponse) -> TVDetailsResult {
        let cast: [CastMemberResult]
        
        if let aggregate = d.aggregate_credits {
            // Sort by episode count descending to ensure leads (like Steve Carell) appear first
            let sortedAggregate = aggregate.cast.sorted { $0.total_episode_count > $1.total_episode_count }
            cast = sortedAggregate.prefix(15).map { member in
                let character = member.roles.first?.character ?? "Unknown"
                return CastMemberResult(name: member.name, character: character, profilePath: member.profile_path, order: member.order)
            }
        } else {
            cast = d.credits?.cast.prefix(15).map { 
                CastMemberResult(name: $0.name, character: $0.character ?? "Unknown", profilePath: $0.profile_path, order: $0.order)
            } ?? []
        }
        
        let creators = d.created_by?.map { 
            CastMemberResult(name: $0.name, character: "Creator", profilePath: $0.profile_path, order: -1)
        } ?? []
        let network = d.networks?.first
        
        var networkLogos: [String: String] = [:]
        for net in d.networks ?? [] {
            networkLogos[net.name] = net.logo_path
        }
        
        let imdbID = d.external_ids?.imdb_id
        let trailerKey = Self.extractTrailerKey(from: d.videos)

        return TVDetailsResult(
            seasonsCount: d.number_of_seasons,
            episodesCount: d.number_of_episodes,
            status: d.status,
            voteAverage: d.vote_average,
            imdbID: imdbID,
            genres: d.genres.map { $0.name },
            backdropPath: d.backdrop_path,
            posterPath: d.poster_path,
            overview: d.overview,
            network: network?.name,
            networkLogoPath: network?.logo_path,
            networkLogos: networkLogos,
            originalLanguage: d.original_language,
            seasons: d.seasons ?? [],
            firstAirDate: d.first_air_date,
            nextEpisodeDate: d.next_episode_to_air?.air_date,
            nextEpisodeNumber: d.next_episode_to_air?.episode_number,
            nextSeasonNumber: d.next_episode_to_air?.season_number,
            tvdbID: d.external_ids?.tvdb_id,
            cast: Array(cast),
            creators: creators,
            trailerKey: trailerKey
        )
    }
    
    // Adaptive Asset Scaling: Restore high quality for Retina displays
    nonisolated var idealThumbnailSize: String {
        return "w780"
    }

    static func tmdbImageURL(path: String?, size: String = "w780") -> String? {
        guard let path = path else { return nil }
        return "https://image.tmdb.org/t/p/\(size)\(path)"
    }

    func fetchSeasonDetails(tmdbID: Int, seasonNumber: Int, force: Bool = false) async throws -> [TVEpisodeResult] {
        let cacheKey = "season_details_\(tmdbID)_\(seasonNumber).json"
        let coalescingKey = cacheKey

        // Check disk cache first (24h TTL for season data, or 7-day if not force)
        let ttl: TimeInterval = force ? .secondsInDay : 7 * .secondsInDay
        if let cachedData = await getCachedData(forKey: cacheKey, ttl: ttl),
           let decoded = try? decoder.decode(TMDBSeasonResponse.self, from: cachedData) {
            return decoded.episodes.map {
                TVEpisodeResult(episodeNumber: $0.episode_number, name: $0.name, overview: $0.overview, airDate: $0.air_date, runtime: $0.runtime)
            }
        }

        // Coalesce concurrent in-flight requests for the same season
        if let existing = inFlightSeasonDetails[coalescingKey] {
            return try await existing.value
        }
        let task = Task<[TVEpisodeResult], Error> {
            defer { self.inFlightSeasonDetails.removeValue(forKey: coalescingKey) }
            do {
                return try await self.executeWithRetry {
                    let url = try self.tmdbURL(path: "/tv/\(tmdbID)/season/\(seasonNumber)")
                    let (data, response) = try await self.session.data(from: url)
                    try self.validateResponse(response)
                    self.saveToCache(data: data, forKey: cacheKey)
                    let decoded = try self.decoder.decode(TMDBSeasonResponse.self, from: data)
                    return decoded.episodes.map {
                        TVEpisodeResult(episodeNumber: $0.episode_number, name: $0.name, overview: $0.overview, airDate: $0.air_date, runtime: $0.runtime)
                    }
                }
            } catch APIError.requestFailed(let code) where code == 404 {
                // TMDB often 404s for Season 0 (Specials) if it's listed in the brief but has no episodes yet.
                AppLogger.debug("ℹ️ Season details not found (404) for show \(tmdbID), season \(seasonNumber). Returning empty.", logger: AppLogger.network)
                return []
            }
        }
        inFlightSeasonDetails[coalescingKey] = task
        return try await task.value
    }

    func searchPerson(query: String) async throws -> String? {
        return try await executeWithRetry {
            let url = try self.tmdbURL(path: "/search/person", queryItems: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "include_adult", value: "false")
            ])
            let (data, response) = try await self.session.data(from: url)
            try self.validateResponse(response)
            let decoded = try self.decoder.decode(TMDBGenericResponse<TMDBPersonSearchEntry>.self, from: data)
            return decoded.results.first?.profile_path
        }
    }

    // MARK: - OMDb Integration

    func fetchOMDBData(imdbID: String) async -> OMDBFullData? {
        let key = omdbApiKey
        guard !key.isEmpty else { return nil }

        // Check disk cache first
        let cacheKey = "omdb_\(imdbID)"
        if let cachedData = await getCachedData(forKey: cacheKey, ttl: .days30),
           let decoded = try? decoder.decode(OMDBResponse.self, from: cachedData),
           let result = decoded.toFullData {
            return result
        }

        guard var components = URLComponents(string: "https://www.omdbapi.com") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "apikey", value: key),
            URLQueryItem(name: "i", value: imdbID)
        ]
        guard let url = components.url else { return nil }

        return try? await executeWithRetry(maxAttempts: 3) {
            let (data, response) = try await self.session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoded = try self.decoder.decode(OMDBResponse.self, from: data)
            if let result = decoded.toFullData {
                self.saveToCache(data: data, forKey: cacheKey)
                return result
            }
            throw URLError(.cannotDecodeContentData)
        }
    }

    // MARK: - TVMaze Integration
    func lookupTVMazeID(tvdbID: Int) async throws -> Int? {
        return try await executeWithRetry {
            var components = URLComponents(string: "https://api.tvmaze.com/lookup/shows")
            components?.queryItems = [URLQueryItem(name: "thetvdb", value: String(tvdbID))]
            guard let url = components?.url else { throw URLError(.badURL) }
            let (data, response) = try await self.session.data(from: url)
            
            try self.validateResponse(response)
            
            let show = try self.decoder.decode(TVMazeShowLookupResponse.self, from: data)
            return show.id
        }
    }

    func lookupTVMazeIDByName(title: String) async throws -> Int? {
        let cacheKey = "tvmaze_name_\(title.lowercased().replacingOccurrences(of: " ", with: "_"))"
        if let cachedData = await getCachedData(forKey: cacheKey, ttl: .secondsInDay),
           let results = try? decoder.decode([TVMazeSearchResult].self, from: cachedData),
           let first = results.first {
            return first.show.id
        }

        return try await executeWithRetry {
            guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://api.tvmaze.com/search/shows?q=\(encoded)") else { throw URLError(.badURL) }
            let (data, response) = try await self.session.data(from: url)
            try self.validateResponse(response)
            let results = try self.decoder.decode([TVMazeSearchResult].self, from: data)
            saveToCache(data: data, forKey: cacheKey)
            return results.first?.show.id
        }
    }

    func fetchTVMazeSchedule(tvMazeID: Int) async throws -> (episode: TVMazeEpisode?, timezone: String?, serviceName: String?, airtime: String?, genres: [String]?) {
        // Check 24h disk cache
        let cacheKey = "tvmaze_schedule_\(tvMazeID)"
        if let cachedData = await getCachedData(forKey: cacheKey, ttl: .secondsInDay),
           let r = try? decoder.decode(TVMazeResponse.self, from: cachedData) {
            return (r._embedded?.nextepisode, r.timezone, r.webChannel?.name ?? r.network?.name, r.schedule?.time, r.genres)
        }

        return try await executeWithRetry {
            guard let url = URL(string: "https://api.tvmaze.com/shows/\(tvMazeID)?embed=nextepisode") else { throw URLError(.badURL) }
            let (data, response) = try await self.session.data(from: url)
            try self.validateResponse(response)
            let r = try self.decoder.decode(TVMazeResponse.self, from: data)
            saveToCache(data: data, forKey: cacheKey)
            return (r._embedded?.nextepisode, r.timezone, r.webChannel?.name ?? r.network?.name, r.schedule?.time, r.genres)
        }
    }

    func fetchTVMazeEpisodes(tvMazeID: Int) async throws -> [TVMazeEpisode] {
        // Check 24h disk cache
        let cacheKey = "tvmaze_episodes_\(tvMazeID)"
        if let cachedData = await getCachedData(forKey: cacheKey, ttl: .secondsInDay) {
            return try decoder.decode([TVMazeEpisode].self, from: cachedData)
        }

        return try await executeWithRetry {
            guard let url = URL(string: "https://api.tvmaze.com/shows/\(tvMazeID)/episodes") else { throw URLError(.badURL) }
            let (data, response) = try await self.session.data(from: url)
            try self.validateResponse(response)
            let result = try self.decoder.decode([TVMazeEpisode].self, from: data)
            saveToCache(data: data, forKey: cacheKey)
            return result
        }
    }

    func fetchTrendingMovies() async throws -> [MediaSearchResult] {
        if let cached = trendingMoviesCache, Date().timeIntervalSince(cached.timestamp) < trendingCacheTTL {
            return cached.data
        }
        let url = try tmdbURL(path: "/trending/movie/day")
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        let decoded = try decoder.decode(TMDBGenericResponse<TMDBMovie>.self, from: data)
        let results = decoded.results.map { $0.toSearchResult() }
        trendingMoviesCache = (results, Date())
        return results
    }

    func fetchTrendingTVShows() async throws -> [MediaSearchResult] {
        if let cached = trendingTVCache, Date().timeIntervalSince(cached.timestamp) < trendingCacheTTL {
            return cached.data
        }
        let url = try tmdbURL(path: "/trending/tv/day")
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        let decoded = try decoder.decode(TMDBGenericResponse<TMDBTV>.self, from: data)
        let results = decoded.results.map { $0.toSearchResult() }
        trendingTVCache = (results, Date())
        return results
    }

    private func executeWithRetry<T: Sendable>(maxAttempts: Int = 5, request: @Sendable () async throws -> T) async throws -> T {
        var attempts = 0
        while attempts < maxAttempts {
            try Task.checkCancellation()
            do {
                return try await request()
            } catch APIError.rateLimited {
                attempts += 1
                if attempts >= maxAttempts { throw APIError.rateLimited }
                let delay = pow(2.0, Double(attempts))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                try Task.checkCancellation()
            } catch {
                let shouldRetry: Bool
                if let urlError = error as? URLError {
                    shouldRetry = urlError.code == .timedOut || urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost || urlError.code == .dnsLookupFailed || urlError.code == .cannotConnectToHost
                } else if let apiError = error as? APIError, case .requestFailed(let code) = apiError {
                    shouldRetry = code >= 500
                } else {
                    shouldRetry = false
                }
                if shouldRetry {
                    attempts += 1
                    if attempts >= maxAttempts { throw error }
                    let delay = pow(2.0, Double(attempts))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw error
            }
        }
        throw APIError.rateLimited
    }
    
    private nonisolated func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 429 { throw APIError.rateLimited }
        if !(200...299).contains(http.statusCode) { throw APIError.requestFailed(http.statusCode) }
    }
}
