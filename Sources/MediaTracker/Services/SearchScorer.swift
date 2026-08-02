import Foundation

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
        var total = 0
        var matchesAll = true
        var matchesAny = false
        for token in tokens {
            let tokenScore = scoreToken(token, item: item)
            total += tokenScore
            matchesAll = matchesAll && tokenScore > 0
            matchesAny = matchesAny || tokenScore > 0
        }

        // Multi-token phrase match in the title dominates per-token matches.
        if tokens.count > 1 {
            let phrase = tokens.joined(separator: " ").lowercased()
            if item.searchTitle == phrase {
                total += 500
            } else if item.searchTitle.contains(phrase) {
                total += 300
            }
        }
        return (total, matchesAll, matchesAny)
    }

    private func scoreToken(_ token: String, item: SearchScorable) -> Int {
        let title = item.searchTitle
        let overview = item.searchOverview
        let creators = item.searchCreators
        let castNames = item.searchCast
        let genres = item.searchGenres
        let network = item.searchNetwork

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
    var searchTitle: String { get }
    var searchOverview: String { get }
    var searchCreators: [String] { get }
    var searchCast: [String] { get }
    var searchGenres: [String] { get }
    var searchNetwork: String? { get }
    var searchableText: String { get }
}

extension MediaItem: SearchScorable {
    var searchTitle: String { title.lowercased() }
    var searchOverview: String { overview.lowercased() }
    var searchCreators: [String] { cachedCreators.map { $0.lowercased() } }
    var searchCast: [String] { displayCast.map { $0.name.lowercased() } }
    var searchGenres: [String] { cachedGenres.map { $0.lowercased() } }
    var searchNetwork: String? { cachedNetwork?.lowercased() }
}

extension MediaSearchResult: SearchScorable {
    var searchTitle: String { title.lowercased() }
    var searchOverview: String { overview.lowercased() }
    var searchCreators: [String] { [] }
    var searchCast: [String] { [] }
    var searchGenres: [String] { genres.map { $0.lowercased() } }
    var searchNetwork: String? { nil }
    var searchableText: String { "\(title) \(overview)".lowercased() }
}
