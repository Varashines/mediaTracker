import Foundation

/// Precomputed lowercased search fields. Building this once per item avoids
/// re-lowercasing every field for every token during multi-token searches.
struct SearchPayload: Sendable {
    let title: String
    let overview: String
    let creators: [String]
    let cast: [String]
    let genres: [String]
    let providers: [String]
    let network: String?
    let language: String?
}

enum SearchMatchSource: Sendable {
    case title
    case creator
    case cast
    case genre
    case provider
    case network
    case language
    case overview

    var isDirect: Bool {
        self != .overview
    }
}

struct SearchEvaluation: Sendable {
    let score: Int
    let matchesAll: Bool
    let matchesAny: Bool
    let hasDirectMatch: Bool

    var isEligibleForAllTokens: Bool {
        matchesAll && hasDirectMatch
    }

    var isEligibleForAnyToken: Bool {
        matchesAny && hasDirectMatch
    }
}

struct SearchScorer: Sendable {
    let tokens: [String]

    init(tokens: [String]) {
        self.tokens = Self.normalizedTokens(tokens)
    }

    static func tokenize(_ query: String) -> [String] {
        normalizedTokens(query.split(separator: " ").map(String.init))
    }

    private static func normalizedTokens(_ tokens: [String]) -> [String] {
        var seen = Set<String>()
        return tokens.compactMap { token in
            let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }

    func score(item: SearchScorable) -> Int {
        evaluate(item: item).score
    }

    func evaluate(item: SearchScorable) -> SearchEvaluation {
        evaluate(payload: item.searchPayload)
    }

    func evaluate(payload: SearchPayload) -> SearchEvaluation {
        var total = 0
        var matchesAll = true
        var matchesAny = false
        var hasDirectMatch = false
        for token in tokens {
            let match = scoreToken(token, payload: payload)
            total += match?.score ?? 0
            matchesAll = matchesAll && match != nil
            matchesAny = matchesAny || match != nil
            hasDirectMatch = hasDirectMatch || match?.source.isDirect == true
        }

        // Multi-token phrase match in the title dominates per-token matches.
        if tokens.count > 1 {
            let phrase = tokens.joined(separator: " ").lowercased()
            if payload.title == phrase {
                total += 500
            } else if payload.title.contains(phrase) {
                total += 300
            }
        }
        return SearchEvaluation(
            score: total,
            matchesAll: matchesAll,
            matchesAny: matchesAny,
            hasDirectMatch: hasDirectMatch
        )
    }

    private func scoreToken(_ token: String, payload: SearchPayload) -> (score: Int, source: SearchMatchSource)? {
        let title = payload.title
        let overview = payload.overview
        let creators = payload.creators
        let castNames = payload.cast
        let genres = payload.genres
        let providers = payload.providers
        let network = payload.network
        let language = payload.language

        // Title scoring — fuzzy and weighted
        if title == token { return (500, .title) }
        let titleWords = title.split(separator: " ").map(String.init)
        if titleWords.contains(token) { return (200, .title) }
        if titleWords.contains(where: { $0.hasPrefix(token) }) { return (150, .title) }
        if title.contains(token) { return (100, .title) }
        if title.count >= 3, token.count >= 3, trigramSimilarity(title, token) > 0.5 { return (50, .title) }

        if let match = scoreField(creators, token: token, exact: 150, partial: 90, source: .creator) {
            return match
        }
        if let match = scoreField(castNames, token: token, exact: 130, partial: 75, source: .cast) {
            return match
        }
        if let match = scoreField(genres, token: token, exact: 120, partial: 70, source: .genre) {
            return match
        }
        if let match = scoreField(providers, token: token, exact: 120, partial: 70, source: .provider) {
            return match
        }
        if let network, let match = scoreField([network], token: token, exact: 100, partial: 55, source: .network) {
            return match
        }
        if let language, let match = scoreField([language], token: token, exact: 100, partial: 55, source: .language) {
            return match
        }
        if overview.localizedStandardContains(token) { return (10, .overview) }

        return nil
    }

    private func scoreField(
        _ values: [String],
        token: String,
        exact: Int,
        partial: Int,
        source: SearchMatchSource
    ) -> (score: Int, source: SearchMatchSource)? {
        if values.contains(where: { $0.localizedStandardCompare(token) == .orderedSame }) {
            return (exact, source)
        }
        if values.contains(where: { $0.localizedStandardContains(token) }) {
            return (partial, source)
        }
        return nil
    }

    /// Each token must contribute at least some score (AND-like)
    func passesAllTokens(item: SearchScorable) -> Bool {
        guard !tokens.isEmpty else { return true }
        return evaluate(item: item).matchesAll
    }

    /// At least one token contributes score (OR-like)
    func passesAnyToken(item: SearchScorable) -> Bool {
        guard !tokens.isEmpty else { return true }
        return evaluate(item: item).matchesAny
    }

    private func trigramSimilarity(_ a: String, _ b: String) -> Double {
        let aTrigrams = trigrams(a.lowercased())
        let bTrigrams = trigrams(b.lowercased())
        guard !aTrigrams.isEmpty, !bTrigrams.isEmpty else { return 0 }
        let intersection = aTrigrams.intersection(bTrigrams).count
        let union = aTrigrams.union(bTrigrams).count
        return Double(intersection) / Double(union)
    }

    private func trigrams(_ s: String) -> Set<String> {
        let chars = Array(s)
        guard chars.count >= 3 else { return [s] }
        var result = Set<String>()
        for i in 0...(chars.count - 3) {
            result.insert(String(chars[i..<i + 3]))
        }
        return result
    }
}

protocol SearchScorable {
    var searchPayload: SearchPayload { get }
    var searchableText: String { get }
}

extension MediaItem: SearchScorable {
    var searchPayload: SearchPayload {
        SearchPayload(
            title: title.lowercased(),
            overview: overview.lowercased(),
            creators: cachedCreators.map { $0.lowercased() },
            cast: displayCast.map { $0.name.lowercased() },
            genres: cachedGenres.map { $0.lowercased() },
            providers: cachedWatchProviders.map { $0.lowercased() },
            network: cachedNetwork?.lowercased(),
            language: cachedLanguage.map {
                let code = $0.lowercased()
                return "\(code) \(LanguageUtils.languageName(for: $0).lowercased())"
            }
        )
    }
}

extension MediaSearchResult: SearchScorable {
    var searchPayload: SearchPayload {
        SearchPayload(
            title: title.lowercased(),
            overview: overview.lowercased(),
            creators: [],
            cast: [],
            genres: genres.map { $0.lowercased() },
            providers: [],
            network: nil,
            language: originalLanguage.map {
                let code = $0.lowercased()
                return "\(code) \(LanguageUtils.languageName(for: $0).lowercased())"
            }
        )
    }
    var searchableText: String { "\(title) \(overview)".lowercased() }
}
