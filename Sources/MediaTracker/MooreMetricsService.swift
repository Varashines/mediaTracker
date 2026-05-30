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
    private let cacheTTL: TimeInterval = .secondsInDay

    private var characteristicsCache: [String: [CharacteristicInfo]] = [:]

    private var apiKey: String {
        UserDefaults.standard.string(forKey: "mm_api_key") ?? ""
    }

    var isConfigured: Bool {
        !apiKey.isEmpty
    }

    // MARK: - Recommend by Items

    func recommend(
        domain: String = "showdive",
        items: [String],
        limit: Int = 10,
        includeCharacteristics: Bool = true
    ) async -> [MooreMetricsRecommendation] {
        guard isConfigured, !items.isEmpty else { return [] }

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
            let labels = await fetchCharacteristics(for: domain)

            let results = response.recommendations.map { rec in
                MooreMetricsRecommendation(
                    id: rec.id,
                    name: rec.name,
                    score: rec.score,
                    characteristics: rec.characteristics ?? [:],
                    reason: deriveReason(from: rec.characteristics ?? [:], labels: labels)
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
        includeCharacteristics: Bool = true
    ) async -> [MooreMetricsRecommendation] {
        guard isConfigured, !preferences.isEmpty else { return [] }

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
            let labels = await fetchCharacteristics(for: domain)

            let results = response.recommendations.map { rec in
                MooreMetricsRecommendation(
                    id: rec.id,
                    name: rec.name,
                    score: rec.score,
                    characteristics: rec.characteristics ?? [:],
                    reason: deriveReason(from: rec.characteristics ?? [:], labels: labels)
                )
            }

            cache[cacheKey] = (data: results, timestamp: Date())
            return results
        } catch {
            AppLogger.debug("MooreMetrics preferences error: \(error)", logger: AppLogger.network)
            return []
        }
    }

    // MARK: - Compute Preference Profile

    func computePreferenceProfile(from itemCharacteristics: [[String: Double]]) -> [String: Double] {
        guard !itemCharacteristics.isEmpty else { return [:] }

        var sums: [String: Double] = [:]
        var counts: [String: Int] = [:]

        for item in itemCharacteristics {
            for (key, value) in item {
                sums[key, default: 0] += value
                counts[key, default: 0] += 1
            }
        }

        var averages: [String: Double] = [:]
        for (key, sum) in sums {
            if let count = counts[key], count > 0 {
                averages[key] = sum / Double(count)
            }
        }

        return averages
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
        var traits: [(String, Double)] = []

        for (key, value) in characteristics {
            if value > 1.0 {
                let label = characteristicLabel(key: key, labels: labels)
                traits.append((label, value))
            }
        }

        traits.sort { $0.1 > $1.1 }

        if traits.isEmpty {
            return "Similar taste"
        }
        return traits.prefix(2).map(\.0).joined(separator: " · ")
    }
}
