import Foundation

enum SmartRule: Codable, Equatable {
    case genre(String)
    case releaseYear(Int, Comparison)
    case releaseYearRange(Int, Int)
    case mediaType(MediaType)
    case state(MediaState)
    case taste(TasteValue)
    case badge(String)
    case network(String)
    case language(String)

    enum Comparison: String, Codable {
        case equals = "is"
        case after = "after"
        case before = "before"
    }

    /// Human-readable rule text ("Genre: Action") for the builder and card summaries.
    var summaryLabel: String {
        switch self {
        case .genre(let g): "Genre: \(g)"
        case .releaseYear(let year, let comp): "Year \(comp.rawValue) \(year)"
        case .releaseYearRange(let start, let end): "Years: \(start)–\(end)"
        case .mediaType(let type): "Type: \(type.rawValue)"
        case .state(let state): "Status: \(state.displayName)"
        case .taste(let taste): "Taste: \(taste.rawValue)"
        case .badge(let b): "Badge: \(b)"
        case .network(let n): "Network: \(n)"
        case .language(let l): "Language: \(LanguageUtils.languageName(for: l))"
        }
    }

    /// SF symbol for the rule row icon.
    var symbolName: String {
        switch self {
        case .genre: "tag.fill"
        case .releaseYear: "calendar"
        case .releaseYearRange: "calendar.badge.clock"
        case .mediaType(let type): type == .movie ? "film" : "tv"
        case .state(let state): state.iconName
        case .taste(let taste): taste.iconName
        case .badge: "sparkles"
        case .network: "antenna.radiowaves.left.and.right"
        case .language: "character.bubble.fill"
        }
    }
}

/// A smart collection's complete rule configuration.
///
/// Stored as JSON in `MediaCollection.smartRulesData`. Decoding falls back to
/// the legacy `[SmartRule]` array format (match-any = false), so pre-wrapper
/// libraries and backups keep working; the upgraded format is written on the
/// next save.
struct SmartRuleSet: Codable, Equatable {
    /// false = Match All (every rule must hold, legacy semantics); true = Match Any (OR).
    var matchAny: Bool = false
    var rules: [SmartRule] = []

    init(matchAny: Bool = false, rules: [SmartRule] = []) {
        self.matchAny = matchAny
        self.rules = rules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchAny = try container.decodeIfPresent(Bool.self, forKey: .matchAny) ?? false
        rules = try container.decodeIfPresent([SmartRule].self, forKey: .rules) ?? []
    }

    /// Short description for cards: "All: X · Y" / "Any of: X, Y", first 3 rules + overflow.
    var summary: String {
        if rules.isEmpty { return "Everything in your library" }
        let prefix = rules.prefix(3).map(\.summaryLabel)
        let joiner = matchAny ? ", " : " · "
        var text = (matchAny ? "Any of: " : "All: ") + prefix.joined(separator: joiner)
        if rules.count > 3 { text += " …+\(rules.count - 3) more" }
        return text
    }
}
