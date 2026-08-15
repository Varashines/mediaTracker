import Foundation

struct MooreMetricsRecommendation: Identifiable, Sendable, Codable {
    let id: String
    let name: String
    let score: Double
    let characteristics: [String: Double]
    let reason: String
}

struct MooreMetricsResponse: Codable, Sendable {
    let domain: String
    let matchedInputs: [MatchedInput]?
    let unmatchedInputs: [String]?
    let count: Int
    let recommendations: [APIRecommendation]

    enum CodingKeys: String, CodingKey {
        case domain
        case matchedInputs = "matched_inputs"
        case unmatchedInputs = "unmatched_inputs"
        case count
        case recommendations
    }
}

struct MatchedInput: Codable, Sendable {
    let input: String
    let matchedTo: String
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case input
        case matchedTo = "matched_to"
        case id
        case name
    }
}

struct APIRecommendation: Codable, Sendable {
    let rank: Int
    let id: String
    let name: String
    let characteristics: [String: Double]?
    let score: Double
}

struct DomainCharacteristics: Codable, Sendable {
    let domain: String
    let entityType: String
    let characteristics: [CharacteristicInfo]

    enum CodingKeys: String, CodingKey {
        case domain
        case entityType = "entity_type"
        case characteristics
    }
}

struct CharacteristicInfo: Codable, Identifiable, Sendable {
    let key: String
    let label: String
    var id: String { key }
}

@MainActor
class MooreMetricsService {
    static let shared = MooreMetricsService()

    private let baseURL = "https://www.mooremetrics.com/wp-json/mooremetrics/v1"
    private let session = URLSession.shared
    private var cache: [String: (data: [MooreMetricsRecommendation], timestamp: Date)] = [:]

    private var cacheTTL: TimeInterval {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.mmDebugMode.rawValue) ? 30 : .secondsInDay
    }

    private var characteristicsCache: [String: [CharacteristicInfo]] = [:]

    private var apiKey: String {
        UserDefaults.standard.string(forKey: UserDefaultsKeys.mmAPIKey.rawValue) ?? ""
    }

    var isConfigured: Bool {
        !apiKey.isEmpty
    }

    private func evictStaleCache() {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.timestamp) < cacheTTL }
    }

    static func recommendedDomain(for item: MediaItem) -> String {
        item.type == .movie ? "moviedive" : "showdive"
    }

    static func recommendedDomain(for items: [MediaItem]) -> String {
        let hasMovies = items.contains { $0.type == .movie }
        let hasTV = items.contains { $0.type == .tvShow }
        if hasMovies && !hasTV { return "moviedive" }
        return "showdive"
    }

    // MARK: - Recommend by Items

    func recommend(
        domain: String = "showdive",
        items: [String],
        limit: Int = 10,
        includeCharacteristics: Bool = true,
        labels: [CharacteristicInfo]? = nil
    ) async -> [MooreMetricsRecommendation] {
        guard isConfigured, !items.isEmpty else { return [] }
        evictStaleCache()

        let cacheKey = "\(domain)_\(items.sorted().joined(separator: ","))"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.data
        }

        guard let url = URL(string: "\(baseURL)/recommend") else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "domain": domain,
            "items": items,
            "limit": limit,
            "include_characteristics": includeCharacteristics
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return []
        }

        do {
            let (data, _) = try await session.data(for: request)
            let response = try JSONDecoder().decode(MooreMetricsResponse.self, from: data)
            let resolvedLabels: [CharacteristicInfo]
            if let labels {
                resolvedLabels = labels
            } else {
                resolvedLabels = await fetchCharacteristics(for: domain)
            }

            let results = response.recommendations.map { rec in
                MooreMetricsRecommendation(
                    id: rec.id,
                    name: rec.name,
                    score: rec.score,
                    characteristics: rec.characteristics ?? [:],
                    reason: deriveReason(from: rec.characteristics ?? [:], labels: resolvedLabels)
                )
            }

            cache[cacheKey] = (data: results, timestamp: Date())
            return results
        } catch {
            AppLogger.debug("MooreMetrics recommend error: \(error)", logger: AppLogger.network)
            return []
        }
    }

    // MARK: - Recommend by Preferences

    func recommendByPreferences(
        domain: String = "showdive",
        preferences: [String: Double],
        limit: Int = 10,
        includeCharacteristics: Bool = true,
        labels: [CharacteristicInfo]? = nil
    ) async -> [MooreMetricsRecommendation] {
        guard isConfigured, !preferences.isEmpty else { return [] }
        evictStaleCache()

        let cacheKey = "pref_\(domain)_\(preferences.map { "\($0.key):\($0.value)" }.sorted().joined(separator: ","))"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.data
        }

        guard let url = URL(string: "\(baseURL)/recommend-by-preferences") else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "domain": domain,
            "preferences": preferences,
            "limit": limit,
            "include_characteristics": includeCharacteristics
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return []
        }

        do {
            let (data, _) = try await session.data(for: request)
            let response = try JSONDecoder().decode(MooreMetricsResponse.self, from: data)
            let resolvedLabels: [CharacteristicInfo]
            if let labels {
                resolvedLabels = labels
            } else {
                resolvedLabels = await fetchCharacteristics(for: domain)
            }

            let results = response.recommendations.map { rec in
                MooreMetricsRecommendation(
                    id: rec.id,
                    name: rec.name,
                    score: rec.score,
                    characteristics: rec.characteristics ?? [:],
                    reason: deriveReason(from: rec.characteristics ?? [:], labels: resolvedLabels)
                )
            }

            cache[cacheKey] = (data: results, timestamp: Date())
            return results
        } catch {
            AppLogger.debug("MooreMetrics preferences error: \(error)", logger: AppLogger.network)
            return []
        }
    }

    // MARK: - Preference Profile Building

    func buildPreferenceProfile(from items: [(characteristics: [String: Double], score: Double)]) -> [String: Double] {
        guard !items.isEmpty else { return [:] }

        let totalWeight = items.reduce(0) { $0 + $1.score }
        guard totalWeight > 0 else { return [:] }

        // Step 1: weighted sums + prevalence counts
        var weightedSums: [String: Double] = [:]
        var prevalenceCounts: [String: Double] = [:]
        var squaredDeviations: [String: Double] = [:]

        for (characteristics, score) in items {
            for (key, value) in characteristics {
                weightedSums[key, default: 0] += value * score
                prevalenceCounts[key, default: 0] += 1
            }
        }

        let itemCount = Double(items.count)
        var averages: [String: Double] = [:]
        var prevalence: [String: Double] = [:]
        for (key, sum) in weightedSums {
            averages[key] = sum / totalWeight
            prevalence[key] = prevalenceCounts[key]! / itemCount
        }

        // Step 2: weighted variance
        for (characteristics, score) in items {
            for (key, avg) in averages {
                let diff = (characteristics[key] ?? 0) - avg
                squaredDeviations[key, default: 0] += score * diff * diff
            }
        }

        var variance: [String: Double] = [:]
        for (key, sum) in squaredDeviations {
            variance[key] = sum / totalWeight
        }

        // Normalize variance to [0, 1]
        let maxVar = variance.values.max() ?? 1
        if maxVar > 0 {
            for key in variance.keys { variance[key]! /= maxVar }
        }

        // Step 3: composite score = avg × prevalence × (1 + normVar)
        var composites: [(key: String, score: Double)] = averages.keys.map {
            ($0, averages[$0]! * prevalence[$0]! * (1 + (variance[$0] ?? 0)))
        }.sorted { $0.score > $1.score }

        guard !composites.isEmpty else { return [:] }

        // Step 4: boost top 2 by 1.5×
        for i in 0..<min(2, composites.count) {
            composites[i].score *= 1.5
        }
        composites.sort { $0.score > $1.score }

        // Step 5: adaptive N — find elbow where drop ratio > 40%
        let minTraits = 2
        let maxTraits = 6
        let traitCount: Int
        if composites.count <= minTraits {
            traitCount = composites.count
        } else {
            var maxDropRatio: Double = 0
            var elbow = composites.count - 1
            for i in 1..<composites.count where composites[i - 1].score > 0 {
                let ratio = (composites[i - 1].score - composites[i].score) / composites[i - 1].score
                if ratio > maxDropRatio {
                    maxDropRatio = ratio
                    elbow = i
                }
            }
            traitCount = maxDropRatio > 0.4
                ? min(max(elbow, minTraits), maxTraits)
                : min(composites.count, maxTraits)
        }

        return composites.prefix(traitCount).reduce(into: [:]) { $0[$1.key] = $1.score }
    }

    func clearCache() {
        cache.removeAll()
        characteristicsCache.removeAll()
        let keys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("mm_rec_cache_") }
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Characteristics

    func fetchCharacteristics(for domain: String) async -> [CharacteristicInfo] {
        if let cached = characteristicsCache[domain] {
            return cached
        }

        guard let url = URL(string: "\(baseURL)/domains/\(domain)/characteristics") else { return [] }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            let (data, _) = try await session.data(for: request)
            let response = try JSONDecoder().decode(DomainCharacteristics.self, from: data)
            characteristicsCache[domain] = response.characteristics
            return response.characteristics
        } catch {
            return []
        }
    }

    func characteristicLabel(key: String, labels: [CharacteristicInfo]) -> String {
        labels.first(where: { $0.key == key })?.label ?? key
    }

    // MARK: - Reason Derivation

    func deriveReason(from characteristics: [String: Double], labels: [CharacteristicInfo] = []) -> String {
        let top = characteristics
            .sorted(by: { $0.value > $1.value })
            .prefix(2)
            .map { characteristicLabel(key: $0.key, labels: labels) }
        return top.isEmpty ? "Similar taste" : top.joined(separator: " · ")
    }
}
