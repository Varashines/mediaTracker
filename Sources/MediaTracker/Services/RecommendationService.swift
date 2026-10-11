import Foundation

enum RecommendationProvider: String, CaseIterable, Identifiable {
    case tmdb = "tmdb"
    case mooremetrics = "mooremetrics"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .tmdb: return "TMDB"
        case .mooremetrics: return "MooreMetrics"
        }
    }
}

enum RecommendationService {
    private static let detailPrefix = "rec_cache_detail_"
    private static let gridPrefix = "rec_cache_"
    private static let thirtyDays: TimeInterval = 30 * 24 * 3600

    static var currentProvider: RecommendationProvider {
        let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.recommendationSource.rawValue) ?? "tmdb"
        return RecommendationProvider(rawValue: raw) ?? .tmdb
    }

    @MainActor
    static func fetchItemRecommendations(
        item: MediaItem
    ) async -> [MooreMetricsRecommendation] {
        let provider = currentProvider
        let mediaType = item.type ?? .movie
        let cacheKey = "rec_\(provider.rawValue)_\(mediaType.rawValue)_\(item.id)"
        if let cached = loadCached(key: cacheKey), !cached.isEmpty {
            return cached
        }

        if provider == .tmdb {
            guard APIClient.shared.isTMDBConfigured else { return [] }
            let tmdbIDInt = Int(item.id.split(separator: "_").last ?? "") ?? Int(item.id) ?? 0
            guard tmdbIDInt > 0 else { return [] }
            do {
                let recs = try await APIClient.shared.fetchTMDBItemRecommendations(
                    mediaType: mediaType,
                    tmdbID: tmdbIDInt
                )
                if !recs.isEmpty {
                    saveCached(key: cacheKey, recommendations: recs)
                }
                return recs
            } catch {
                return []
            }
        } else {
            let domain = MooreMetricsService.recommendedDomain(for: item)
            return await fetchRecommendations(
                titles: [item.title],
                domain: domain,
                cachePrefix: "mm_rec_cache_detail_",
                cacheKey: "\(domain)_\(item.title)"
            )
        }
    }

    static func fetchRecommendations(
        titles: [String],
        domain: String,
        cachePrefix: String,
        cacheKey: String,
        normalizer: (@Sendable (MooreMetricsRecommendation) -> MooreMetricsRecommendation)? = nil
    ) async -> [MooreMetricsRecommendation] {
        guard await MooreMetricsService.shared.isConfigured else { return [] }
        guard !titles.isEmpty else { return [] }

        if let cached = loadCached(key: cachePrefix + cacheKey), !cached.isEmpty {
            return cached
        }

        async let asyncLabels = MooreMetricsService.shared.fetchCharacteristics(for: domain)
        var results = await MooreMetricsService.shared.recommend(
            domain: domain, items: titles, limit: 10, labels: await asyncLabels
        )
        guard !results.isEmpty else { return [] }

        if results.count >= 3 {
            let profile = await MooreMetricsService.shared.buildPreferenceProfile(
                from: results.map { ($0.characteristics, $0.score) }
            )
            if !profile.isEmpty {
                let prefResults = await MooreMetricsService.shared.recommendByPreferences(
                    domain: domain, preferences: profile, limit: 5, labels: await asyncLabels
                )
                var seen = Set(results.map(\.name))
                for rec in prefResults where !seen.contains(rec.name) {
                    results.append(rec)
                    seen.insert(rec.name)
                }
            }
        }

        var finalResults = Array(results.prefix(10))
        if let normalizer = normalizer {
            finalResults = finalResults.map(normalizer)
        }

        saveCached(key: cachePrefix + cacheKey, recommendations: finalResults)
        return finalResults
    }

    private static func saveCached(key: String, recommendations: [MooreMetricsRecommendation]) {
        if let data = try? JSONEncoder().encode(recommendations) {
            UserDefaults.standard.set(data, forKey: key)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key + "_ts")
        }
    }

    private static func loadCached(key: String) -> [MooreMetricsRecommendation]? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cached = try? JSONDecoder().decode([MooreMetricsRecommendation].self, from: data),
              !cached.isEmpty,
              let timestamp = UserDefaults.standard.object(forKey: key + "_ts") as? TimeInterval,
              Date().timeIntervalSince1970 - timestamp < thirtyDays else {
            return nil
        }
        return cached
    }
}
