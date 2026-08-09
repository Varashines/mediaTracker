import Foundation

/// Precomputed lowercased search fields. Building this once per item avoids
/// re-lowercasing every field for every token during multi-token searches.
struct SearchPayload: Sendable {
    let title: String
    let overview: String
    let creators: [String]
    let cast: [String]
    let genres: [String]
    let network: String?
    let language: String?
}

struct SearchScorer: Sendable {
    let tokens: [String]
    private let tokenSet: Set<String>

    init(tokens: [String]) {
        self.tokens = tokens
        self.tokenSet = Set(tokens)
    }

    func score(item: SearchScorable) -> Int {
        evaluate(item: item).score
    }

    func evaluate(item: SearchScorable) -> (score: Int, matchesAll: Bool, matchesAny: Bool) {
        evaluate(payload: item.searchPayload)
    }

    func evaluate(payload: SearchPayload) -> (score: Int, matchesAll: Bool, matchesAny: Bool) {
        var total = 0
        var matchesAll = true
        var matchesAny = false
        for token in tokens {
            let tokenScore = scoreToken(token, payload: payload)
            total += tokenScore
            matchesAll = matchesAll && tokenScore > 0
            matchesAny = matchesAny || tokenScore > 0
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
        return (total, matchesAll, matchesAny)
    }

    private func scoreToken(_ token: String, payload: SearchPayload) -> Int {
        let title = payload.title
        let overview = payload.overview
        let creators = payload.creators
        let castNames = payload.cast
        let genres = payload.genres
        let network = payload.network
        let language = payload.language

        // Title scoring — fuzzy and weighted
        if title == token { return 500 }
        let titleWords = title.split(separator: " ").map(String.init)
        if titleWords.contains(token) { return 200 }
        if titleWords.contains(where: { $0.hasPrefix(token) }) { return 150 }
        if title.contains(token) { return 100 }
        if title.count >= 3, token.count >= 3, trigramSimilarity(title, token) > 0.5 { return 50 }

        // Other fields — exact or contains
        if creators.contains(where: { $0.localizedStandardContains(token) }) { return 80 }
        if castNames.contains(where: { $0.localizedStandardContains(token) }) { return 60 }
        if genres.contains(where: { $0.localizedStandardContains(token) }) { return 30 }
        if overview.localizedStandardContains(token) { return 15 }
        if let net = network, net.localizedStandardContains(token) { return 10 }
        if let lang = language, lang.localizedStandardContains(token) { return 10 }

        return 0
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
            network: nil,
            language: originalLanguage.map {
                let code = $0.lowercased()
                return "\(code) \(LanguageUtils.languageName(for: $0).lowercased())"
            }
        )
    }
    var searchableText: String { "\(title) \(overview)".lowercased() }
}
