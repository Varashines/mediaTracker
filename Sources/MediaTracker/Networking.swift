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
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            directory: nil
        )
        return URLSession(configuration: config)
    }()
    
    // Phase 2: Search Cache
    private var inFlightTasks: [String: Task<[MediaSearchResult], Error>] = [:]
    private var searchCache: [String: [MediaSearchResult]] = [:]
    private var lastSearchTime: [String: Date] = [:]
    private let cacheExpiry: TimeInterval = 300 // 5 minutes

    // In-flight task coalescing: prevents concurrent duplicate network requests for the same resource
    private var inFlightMovieDetails: [Int: Task<MovieDetailsResult, Error>] = [:]
    private var inFlightTVDetails: [Int: Task<TVDetailsResult, Error>] = [:]
    private var inFlightSeasonDetails: [String: Task<[TVEpisodeResult], Error>] = [:]
    
    private nonisolated var tmdbApiKey: String { UserDefaults.standard.string(forKey: UserDefaultsKeys.tmdbAPIKey.rawValue) ?? "" }
    private nonisolated var omdbApiKey: String { UserDefaults.standard.string(forKey: UserDefaultsKeys.omdbAPIKey.rawValue) ?? "" }

    init() {
        // Compute and create the cache directory exactly once instead of on every getCachedData/saveToCache call
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = paths.first ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("api_details_cache")
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        self.cacheFolder = folder
    }

    private func clearSearchCache() {
        searchCache.removeAll()
        lastSearchTime.removeAll()
    }

    func clearMemoryCaches() {
        clearSearchCache()
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
    private func getCachedData(forKey key: String) async -> Data? {
        let fileURL = cacheFolder.appendingPathComponent(key)
        
        return await FileIOActor.shared.run {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let modificationDate = attributes[.modificationDate] as? Date,
                  Date().timeIntervalSince(modificationDate) < (7 * 86400) else { // 7 day cache
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
        if !force, let cachedData = await getCachedData(forKey: cacheKey),
           let details = try? decoder.decode(TMDBMovieDetailsResponse.self, from: cachedData) {
            return processMovieDetails(details)
        }

        // Coalesce concurrent in-flight requests for the same movie to share one network call
        if !force, let existing = inFlightMovieDetails[tmdbID] {
            return try await existing.value
        }
        let task = Task<MovieDetailsResult, Error> {
            defer { self.inFlightMovieDetails.removeValue(forKey: tmdbID) }
            return try await self.executeWithRetry {
                let url = try self.tmdbURL(path: "/movie/\(tmdbID)", queryItems: [URLQueryItem(name: "append_to_response", value: "credits,release_dates,external_ids")])
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
            productionCompanies: productionCompanies
        )
    }

    func fetchTVDetails(tmdbID: Int, force: Bool = false) async throws -> TVDetailsResult {
        let cacheKey = "tv_details_\(tmdbID).json"
        if !force, let cachedData = await getCachedData(forKey: cacheKey),
           let d = try? decoder.decode(TMDBTVDetailsResponse.self, from: cachedData) {
            return processTVDetails(d)
        }

        // Coalesce concurrent in-flight requests for the same show to share one network call
        if !force, let existing = inFlightTVDetails[tmdbID] {
            return try await existing.value
        }
        let task = Task<TVDetailsResult, Error> {
            defer { self.inFlightTVDetails.removeValue(forKey: tmdbID) }
            return try await self.executeWithRetry {
                let url = try self.tmdbURL(path: "/tv/\(tmdbID)", queryItems: [URLQueryItem(name: "append_to_response", value: "external_ids,aggregate_credits")])
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
        
        let imdbID = d.external_ids?.imdb_id

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
            originalLanguage: d.original_language,
            seasons: d.seasons ?? [],
            firstAirDate: d.first_air_date,
            nextEpisodeDate: d.next_episode_to_air?.air_date,
            nextEpisodeNumber: d.next_episode_to_air?.episode_number,
            nextSeasonNumber: d.next_episode_to_air?.season_number,
            tvdbID: d.external_ids?.tvdb_id,
            cast: Array(cast),
            creators: creators
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

    func fetchSeasonDetails(tmdbID: Int, seasonNumber: Int) async throws -> [TVEpisodeResult] {
        let cacheKey = "season_details_\(tmdbID)_\(seasonNumber).json"
        let coalescingKey = cacheKey

        // Check disk cache first (24h TTL for season data)
        if let cachedData = await getCachedData(forKey: cacheKey),
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
        var components = URLComponents(string: "https://www.omdbapi.com")!
        components.queryItems = [
            URLQueryItem(name: "apikey", value: key),
            URLQueryItem(name: "i", value: imdbID)
        ]
        guard let url = components.url else { return nil }
        
        for _ in 0..<3 {
            guard let (data, response) = try? await session.data(from: url),
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let decoded = try? decoder.decode(OMDBResponse.self, from: data)
            else {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }
            if let result = decoded.toFullData { return result }
            return nil
        }
        return nil
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

    func fetchTVMazeSchedule(tvMazeID: Int) async throws -> (episode: TVMazeEpisode?, timezone: String?, serviceName: String?, airtime: String?) {
        return try await executeWithRetry {
            let url = URL(string: "https://api.tvmaze.com/shows/\(tvMazeID)?embed=nextepisode")!
            let (data, response) = try await self.session.data(from: url)
            try self.validateResponse(response)
            let r = try self.decoder.decode(TVMazeResponse.self, from: data)
            return (r._embedded?.nextepisode, r.timezone, r.webChannel?.name ?? r.network?.name, r.schedule?.time)
        }
    }

    func fetchTVMazeEpisodes(tvMazeID: Int) async throws -> [TVMazeEpisode] {
        return try await executeWithRetry {
            let url = URL(string: "https://api.tvmaze.com/shows/\(tvMazeID)/episodes")!
            let (data, response) = try await self.session.data(from: url)
            try self.validateResponse(response)
            return try self.decoder.decode([TVMazeEpisode].self, from: data)
        }
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
                // If it's a generic request failure, don't retry unless it's a timeout or network loss
                if let urlError = error as? URLError, (urlError.code == .timedOut || urlError.code == .notConnectedToInternet) {
                    attempts += 1
                    if attempts >= maxAttempts { throw error }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
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
