import Foundation

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

    // In-memory watch provider cache (populated during processMovieDetails/processTVDetails)
    private var providerCache: [Int: [WatchProviderResult]] = [:]

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

    private func searchCacheKey(prefix: String, query: String) -> String {
        let safeQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_."))) ?? "query"
        return "\(prefix)_\(safeQuery)"
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
        
        let percentEncodedItems = items.map { item -> URLQueryItem in
            let encodedName = item.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
                .replacingOccurrences(of: "/", with: "%2F") ?? item.name
            let encodedValue = item.value?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
                .replacingOccurrences(of: "/", with: "%2F")
            return URLQueryItem(name: encodedName, value: encodedValue)
        }
        components?.percentEncodedQueryItems = percentEncodedItems
        
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
        let cacheKey = searchCacheKey(prefix: "search_movie", query: query)
        
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
        let cacheKey = searchCacheKey(prefix: "search_tv", query: query)
        
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
        let cacheKey = "movie_details_v2_\(tmdbID).json"
        if !force,
           let cachedData = await getCachedData(forKey: cacheKey, ttl: 7 * .secondsInDay),
           let details = try? decoder.decode(TMDBMovieDetailsResponse.self, from: cachedData) {
            let result = processMovieDetails(details)
            if !result.streamingProviders.isEmpty { providerCache[tmdbID] = result.streamingProviders }
            return result
        }

        if let existing = inFlightMovieDetails[tmdbID] {
            return try await existing.value
        }
        let task = Task<MovieDetailsResult, Error> {
            defer { self.inFlightMovieDetails.removeValue(forKey: tmdbID) }
            let result = try await self.executeWithRetry {
                let appendParts = force ? "credits,release_dates,external_ids,videos,watch/providers" : "credits,external_ids,videos,watch/providers"
                let url = try self.tmdbURL(path: "/movie/\(tmdbID)", queryItems: [URLQueryItem(name: "append_to_response", value: appendParts)])
                let (data, response) = try await self.session.data(from: url)
                try self.validateResponse(response)
                self.saveToCache(data: data, forKey: cacheKey)
                let details = try self.decoder.decode(TMDBMovieDetailsResponse.self, from: data)
                return self.processMovieDetails(details)
            }
            if !result.streamingProviders.isEmpty { self.providerCache[tmdbID] = result.streamingProviders }
            return result
        }
        inFlightMovieDetails[tmdbID] = task
        return try await task.value
    }

    private nonisolated func processMovieDetails(_ details: TMDBMovieDetailsResponse) -> MovieDetailsResult {
        let cast: [CastMemberResult] = details.credits?.cast.prefix(30).compactMap { member in
            guard let name = member.name, !name.isEmpty else { return nil }
            return CastMemberResult(name: name, character: member.character ?? "Unknown", profilePath: member.profile_path, order: member.order)
        } ?? []
        
        let directors: [CastMemberResult] = details.credits?.crew?.filter { $0.job == "Director" }.compactMap { member in
            guard let name = member.name, !name.isEmpty else { return nil }
            return CastMemberResult(name: name, character: "Director", profilePath: member.profile_path, order: -1)
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
            status: details.status,
            cast: Array(cast), 
            directors: directors,
            productionCompanies: productionCompanies,
            trailerKey: trailerKey,
            streamingProviders: extractWatchProviders(from: details.watch_providers)
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
        let cacheKey = "tv_details_v2_\(tmdbID).json"
        if force {
            removeCachedResponse(forKey: cacheKey)
        } else if let cachedData = await getCachedData(forKey: cacheKey, ttl: 7 * .secondsInDay),
           let d = try? decoder.decode(TMDBTVDetailsResponse.self, from: cachedData) {
            let result = processTVDetails(d)
            if !result.streamingProviders.isEmpty { providerCache[tmdbID] = result.streamingProviders }
            return result
        }

        // Coalesce concurrent in-flight requests for the same show to share one network call
        // Only coalesce non-force requests — force requests always fetch fresh data
        if !force, let existing = inFlightTVDetails[tmdbID] {
            return try await existing.value
        }
        let task = Task<TVDetailsResult, Error> {
            defer { self.inFlightTVDetails.removeValue(forKey: tmdbID) }
            let result = try await self.executeWithRetry {
                let url = try self.tmdbURL(path: "/tv/\(tmdbID)", queryItems: [URLQueryItem(name: "append_to_response", value: "external_ids,credits,aggregate_credits,videos,watch/providers")])
                let (data, response) = try await self.session.data(from: url)
                try self.validateResponse(response)
                self.saveToCache(data: data, forKey: cacheKey)
                let d = try self.decoder.decode(TMDBTVDetailsResponse.self, from: data)
                return self.processTVDetails(d)
            }
            if !result.streamingProviders.isEmpty { self.providerCache[tmdbID] = result.streamingProviders }
            return result
        }
        inFlightTVDetails[tmdbID] = task
        return try await task.value
    }

    private nonisolated func processTVDetails(_ d: TMDBTVDetailsResponse) -> TVDetailsResult {
        let cast: [CastMemberResult]
        
        if let aggregate = d.aggregate_credits {
            // Sort by episode count descending to ensure leads (like Steve Carell) appear first
            let sortedAggregate = aggregate.cast.sorted { $0.total_episode_count > $1.total_episode_count }
            cast = sortedAggregate.prefix(30).compactMap { member in
                guard let name = member.name, !name.isEmpty else { return nil }
                let character = member.roles.first?.character ?? "Unknown"
                return CastMemberResult(name: name, character: character, profilePath: member.profile_path, order: member.order)
            }
        } else {
            cast = d.credits?.cast.prefix(15).compactMap { member in
                guard let name = member.name, !name.isEmpty else { return nil }
                return CastMemberResult(name: name, character: member.character ?? "Unknown", profilePath: member.profile_path, order: member.order)
            } ?? []
        }
        
        var creators: [CastMemberResult] = []
        if let createdBy = d.created_by {
            creators = createdBy.compactMap { p in
                guard let name = p.name, !name.isEmpty else { return nil }
                return CastMemberResult(name: name, character: "Creator", profilePath: p.profile_path, order: -1)
            }
        }

        if creators.isEmpty {
            let crew = d.aggregate_credits?.crew ?? d.credits?.crew ?? []
            let showrunners = crew.compactMap { member -> (name: String, job: String, profilePath: String?)? in
                guard let name = member.name, !name.isEmpty else { return nil }
                guard let job = member.job?.lowercased() else { return nil }
                if job == "creator" || job == "showrunner" || job == "executive producer" || job == "director" {
                    return (name: name, job: member.job ?? "Creator", profilePath: member.profile_path)
                }
                return nil
            }
            var seen = Set<String>()
            for member in showrunners {
                if !seen.contains(member.name) {
                    seen.insert(member.name)
                    creators.append(CastMemberResult(name: member.name, character: member.job, profilePath: member.profilePath, order: -1))
                    if creators.count >= 3 { break }
                }
            }
        }
        let network = d.networks?.first?.name
        
        let imdbID = d.external_ids?.imdb_id
        let trailerKey = Self.extractTrailerKey(from: d.videos)

        return TVDetailsResult(
            status: d.status ?? "Ended",
            voteAverage: d.vote_average,
            imdbID: imdbID,
            genres: d.genres?.compactMap { $0.name } ?? [],
            backdropPath: d.backdrop_path,
            posterPath: d.poster_path,
            overview: d.overview,
            network: network,
            networkLogoPath: d.networks?.first?.logo_path,
            originalLanguage: d.original_language,
            seasons: d.seasons ?? [],
            firstAirDate: d.first_air_date,
            nextEpisodeDate: d.next_episode_to_air?.air_date,
            nextEpisodeNumber: d.next_episode_to_air?.episode_number,
            nextSeasonNumber: d.next_episode_to_air?.season_number,
            tvdbID: d.external_ids?.tvdb_id,
            cast: Array(cast),
            creators: creators,
            trailerKey: trailerKey,
            streamingProviders: extractWatchProviders(from: d.watch_providers)
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

    func fetchWatchProviders(tmdbID: Int, type: MediaType) async -> [WatchProviderResult] {
        // Primary: in-memory cache (populated during fetchMovieDetails/fetchTVDetails)
        if let cached = providerCache[tmdbID], !cached.isEmpty {
            return cached
        }
        // Fallback 1: disk cache (for items refreshed before this session)
        let cacheKey = type == .movie ? "movie_details_v2_\(tmdbID).json" : "tv_details_v2_\(tmdbID).json"
        if let cachedData = await getCachedData(forKey: cacheKey, ttl: 7 * .secondsInDay) {
            if type == .movie {
                if let d = try? decoder.decode(TMDBMovieDetailsResponse.self, from: cachedData) {
                    let providers = extractWatchProviders(from: d.watch_providers)
                    if !providers.isEmpty {
                        providerCache[tmdbID] = providers
                        return providers
                    }
                }
            } else {
                if let d = try? decoder.decode(TMDBTVDetailsResponse.self, from: cachedData) {
                    let providers = extractWatchProviders(from: d.watch_providers)
                    if !providers.isEmpty {
                        providerCache[tmdbID] = providers
                        return providers
                    }
                }
            }
        }
        
        // Fallback 2: dedicated watch providers endpoint
        let path = type == .movie ? "/movie/\(tmdbID)/watch/providers" : "/tv/\(tmdbID)/watch/providers"
        do {
            let url = try tmdbURL(path: path)
            let (data, response) = try await session.data(from: url)
            try validateResponse(response)
            let decoded = try decoder.decode(TMDBWatchProvidersResponse.self, from: data)
            let providers = extractWatchProviders(from: decoded)
            providerCache[tmdbID] = providers
            return providers
        } catch {
            AppLogger.warning("Failed to fetch watch providers online for \(type) \(tmdbID): \(error)", logger: AppLogger.background)
            return []
        }
    }

    func fetchSeasonDetails(tmdbID: Int, seasonNumber: Int, force: Bool = false) async throws -> [TVEpisodeResult] {
        let cacheKey = "season_details_\(tmdbID)_\(seasonNumber).json"
        let coalescingKey = cacheKey

        // Check disk cache first (24h TTL for season data, or 7-day if not force)
        let ttl: TimeInterval = force ? -1 : 7 * .secondsInDay
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

    // MARK: - Title Logos

    func fetchMovieLogos(tmdbID: Int, originalLanguage: String? = nil, force: Bool = false) async throws -> [String] {
        let cacheKey = "movie_logos_\(tmdbID).json"
        let ttl: TimeInterval = force ? -1 : 30 * .secondsInDay

        if !force,
           let cachedData = await getCachedData(forKey: cacheKey, ttl: ttl),
           let decoded = try? decoder.decode(TMDBImagesResponse.self, from: cachedData) {
            return Self.processLogoURLs(decoded.logos, originalLanguage: originalLanguage)
        }

        return try await executeWithRetry {
            let url = try self.tmdbURL(path: "/movie/\(tmdbID)/images", queryItems: [
                URLQueryItem(name: "include_image_language", value: "en,null")
            ])
            let (data, response) = try await self.session.data(from: url)
            try self.validateResponse(response)
            self.saveToCache(data: data, forKey: cacheKey)
            let decoded = try self.decoder.decode(TMDBImagesResponse.self, from: data)
            return Self.processLogoURLs(decoded.logos, originalLanguage: originalLanguage)
        }
    }

    func fetchTVLogos(tmdbID: Int, originalLanguage: String? = nil, force: Bool = false) async throws -> [String] {
        let cacheKey = "tv_logos_\(tmdbID).json"
        let ttl: TimeInterval = force ? -1 : 30 * .secondsInDay

        if !force,
           let cachedData = await getCachedData(forKey: cacheKey, ttl: ttl),
           let decoded = try? decoder.decode(TMDBImagesResponse.self, from: cachedData) {
            return Self.processLogoURLs(decoded.logos, originalLanguage: originalLanguage)
        }

        return try await executeWithRetry {
            let url = try self.tmdbURL(path: "/tv/\(tmdbID)/images", queryItems: [
                URLQueryItem(name: "include_image_language", value: "en,null")
            ])
            let (data, response) = try await self.session.data(from: url)
            try self.validateResponse(response)
            self.saveToCache(data: data, forKey: cacheKey)
            let decoded = try self.decoder.decode(TMDBImagesResponse.self, from: data)
            return Self.processLogoURLs(decoded.logos, originalLanguage: originalLanguage)
        }
    }

    private nonisolated static func processLogoURLs(_ logos: [TMDBLogo]?, originalLanguage: String? = nil) -> [String] {
        guard let logos else { return [] }
        
        // Prioritize: original language > English > null > others
        return logos
            .sorted { a, b in
                let aScore = logoPriority(a, originalLanguage: originalLanguage)
                let bScore = logoPriority(b, originalLanguage: originalLanguage)
                if aScore != bScore { return aScore < bScore }
                return a.width > b.width // Prefer larger logos as tiebreaker
            }
            .compactMap { Self.tmdbImageURL(path: $0.file_path, size: "w780") }
    }
    
    private nonisolated static func logoPriority(_ logo: TMDBLogo, originalLanguage: String?) -> Int {
        let lang = logo.iso_639_1
        if let originalLanguage, lang == originalLanguage { return 0 } // Original language = highest priority
        if lang == "en" { return 1 } // English = second priority
        if lang == nil { return 2 } // No language = third priority
        return 3 // Other languages = lowest priority
    }

    // MARK: - Poster Options

    func fetchMoviePosters(tmdbID: Int, originalLanguage: String? = nil, force: Bool = false) async throws -> [String] {
        let cacheKey = "movie_posters_\(tmdbID).json"
        let ttl: TimeInterval = force ? -1 : 30 * .secondsInDay

        if !force,
           let cachedData = await getCachedData(forKey: cacheKey, ttl: ttl),
           let decoded = try? decoder.decode(TMDBImagesResponse.self, from: cachedData) {
            return Self.processPosterURLs(decoded.posters, originalLanguage: originalLanguage)
        }

        return try await executeWithRetry {
            let url = try self.tmdbURL(path: "/movie/\(tmdbID)/images", queryItems: [
                URLQueryItem(name: "include_image_language", value: "en,null")
            ])
            let (data, response) = try await self.session.data(from: url)
            try self.validateResponse(response)
            self.saveToCache(data: data, forKey: cacheKey)
            let decoded = try self.decoder.decode(TMDBImagesResponse.self, from: data)
            return Self.processPosterURLs(decoded.posters, originalLanguage: originalLanguage)
        }
    }

    func fetchTVPosters(tmdbID: Int, originalLanguage: String? = nil, force: Bool = false) async throws -> [String] {
        let cacheKey = "tv_posters_\(tmdbID).json"
        let ttl: TimeInterval = force ? -1 : 30 * .secondsInDay

        if !force,
           let cachedData = await getCachedData(forKey: cacheKey, ttl: ttl),
           let decoded = try? decoder.decode(TMDBImagesResponse.self, from: cachedData) {
            return Self.processPosterURLs(decoded.posters, originalLanguage: originalLanguage)
        }

        return try await executeWithRetry {
            let url = try self.tmdbURL(path: "/tv/\(tmdbID)/images", queryItems: [
                URLQueryItem(name: "include_image_language", value: "en,null")
            ])
            let (data, response) = try await self.session.data(from: url)
            try self.validateResponse(response)
            self.saveToCache(data: data, forKey: cacheKey)
            let decoded = try self.decoder.decode(TMDBImagesResponse.self, from: data)
            return Self.processPosterURLs(decoded.posters, originalLanguage: originalLanguage)
        }
    }

    private nonisolated static func processPosterURLs(_ posters: [TMDBPoster]?, originalLanguage: String? = nil) -> [String] {
        guard let posters else { return [] }

        // Prioritize: null language (clean) > original language > English > others, then by vote_average
        return posters
            .sorted { a, b in
                let aScore = posterPriority(a, originalLanguage: originalLanguage)
                let bScore = posterPriority(b, originalLanguage: originalLanguage)
                if aScore != bScore { return aScore < bScore }
                let aVotes = a.vote_average ?? 0
                let bVotes = b.vote_average ?? 0
                return aVotes > bVotes
            }
            .compactMap { Self.tmdbImageURL(path: $0.file_path, size: "w780") }
    }

    private nonisolated static func posterPriority(_ poster: TMDBPoster, originalLanguage: String?) -> Int {
        let lang = poster.iso_639_1
        if lang == nil { return 0 } // No language (clean poster) = highest priority
        if let originalLanguage, lang == originalLanguage { return 1 } // Original language = second priority
        if lang == "en" { return 2 } // English = third priority
        return 3 // Other languages = lowest priority
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

    func fetchTVMazeSchedule(tvMazeID: Int) async throws -> (episode: TVMazeEpisode?, timezone: String?, serviceName: String?, airtime: String?, genres: [String]?, showType: String?) {
        // Check 24h disk cache
        let cacheKey = "tvmaze_schedule_\(tvMazeID)"
        if let cachedData = await getCachedData(forKey: cacheKey, ttl: .secondsInDay),
           let r = try? decoder.decode(TVMazeResponse.self, from: cachedData) {
            return (r._embedded?.nextepisode, r.timezone, r.webChannel?.name ?? r.network?.name, r.schedule?.time, r.genres, r.type)
        }

        return try await executeWithRetry {
            guard let url = URL(string: "https://api.tvmaze.com/shows/\(tvMazeID)?embed=nextepisode") else { throw URLError(.badURL) }
            let (data, response) = try await self.session.data(from: url)
            try self.validateResponse(response)
            let r = try self.decoder.decode(TVMazeResponse.self, from: data)
            saveToCache(data: data, forKey: cacheKey)
            return (r._embedded?.nextepisode, r.timezone, r.webChannel?.name ?? r.network?.name, r.schedule?.time, r.genres, r.type)
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

    // MARK: - Key Validation

    /// Validates a TMDB API key with a lightweight /configuration request.
    func validateTMDBKey(key: String) async -> Bool {
        guard !key.isEmpty else { return false }
        var components = URLComponents(string: "https://api.themoviedb.org/3/configuration")
        components?.queryItems = [URLQueryItem(name: "api_key", value: key)]
        guard let url = components?.url else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            try validateResponse(response)
            return true
        } catch {
            return false
        }
    }

    /// Validates an OMDb API key with a lightweight query against the endpoint.
    func validateOMDBKey(key: String) async -> Bool {
        guard !key.isEmpty else { return false }
        var components = URLComponents(string: "https://www.omdbapi.com")
        components?.queryItems = [URLQueryItem(name: "apikey", value: key)]
        guard let url = components?.url else { return false }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return false }
            let decoded = try? decoder.decode(OMDBResponse.self, from: data)
            return decoded?.isSuccess == true
        } catch {
            return false
        }
    }
}
