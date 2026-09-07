import Foundation

enum SmartRule: Codable, Equatable {
    case genre([String])
    case releaseYear(Int, Comparison)
    case releaseYearRange(Int, Int)
    case mediaType([MediaType])
    case state([MediaState])
    case taste([TasteValue])
    case badge([String])
    case network([String])
    case language([String])

    // Convenience single-value constructors for backward-compatible call sites
    static func genre(_ single: String) -> SmartRule { .genre([single]) }
    static func mediaType(_ single: MediaType) -> SmartRule { .mediaType([single]) }
    static func state(_ single: MediaState) -> SmartRule { .state([single]) }
    static func taste(_ single: TasteValue) -> SmartRule { .taste([single]) }
    static func badge(_ single: String) -> SmartRule { .badge([single]) }
    static func network(_ single: String) -> SmartRule { .network([single]) }
    static func language(_ single: String) -> SmartRule { .language([single]) }

    enum Comparison: String, Codable {
        case equals = "is"
        case after = "after"
        case before = "before"
    }

    /// Human-readable rule text ("Genre: Action, Comedy") for the builder and card summaries.
    var summaryLabel: String {
        switch self {
        case .genre(let g):
            let names = g.joined(separator: ", ")
            return g.count > 1 ? "Genres: \(names)" : "Genre: \(names)"
        case .releaseYear(let year, let comp):
            return "Year \(comp.rawValue) \(year)"
        case .releaseYearRange(let start, let end):
            return "Years: \(start)–\(end)"
        case .mediaType(let types):
            let names = types.map(\.rawValue).joined(separator: ", ")
            return types.count > 1 ? "Types: \(names)" : "Type: \(names)"
        case .state(let states):
            let names = states.map(\.displayName).joined(separator: ", ")
            return states.count > 1 ? "Statuses: \(names)" : "Status: \(names)"
        case .taste(let tastes):
            let names = tastes.map(\.rawValue).joined(separator: ", ")
            return tastes.count > 1 ? "Tastes: \(names)" : "Taste: \(names)"
        case .badge(let b):
            let names = b.joined(separator: ", ")
            return b.count > 1 ? "Badges: \(names)" : "Badge: \(names)"
        case .network(let n):
            let names = n.joined(separator: ", ")
            return n.count > 1 ? "Networks: \(names)" : "Network: \(names)"
        case .language(let l):
            let names = l.map { LanguageUtils.languageName(for: $0) }.joined(separator: ", ")
            return l.count > 1 ? "Languages: \(names)" : "Language: \(names)"
        }
    }

    /// SF symbol for the rule row icon.
    var symbolName: String {
        switch self {
        case .genre: "tag.fill"
        case .releaseYear: "calendar"
        case .releaseYearRange: "calendar.badge.clock"
        case .mediaType(let types): types.count == 1 && types.first == .movie ? "film" : "tv"
        case .state(let states): states.count == 1 ? (states.first?.iconName ?? "circle") : "checkmark.circle.badge.questionmark"
        case .taste(let tastes): tastes.count == 1 ? (tastes.first?.iconName ?? "heart") : "heart.fill"
        case .badge: "sparkles"
        case .network: "antenna.radiowaves.left.and.right"
        case .language: "character.bubble.fill"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case genre
        case releaseYear
        case releaseYearRange
        case mediaType
        case state
        case taste
        case badge
        case network
        case language
    }

    private struct SingleAssociated<T: Codable>: Codable {
        let _0: T
    }

    private struct DoubleAssociated<T: Codable, U: Codable>: Codable {
        let _0: T
        let _1: U
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.genre) {
            // Support either array [String] or single String
            if let arrayPayload = try? container.decode(SingleAssociated<[String]>.self, forKey: .genre) {
                self = .genre(arrayPayload._0)
            } else if let singlePayload = try? container.decode(SingleAssociated<String>.self, forKey: .genre) {
                self = .genre([singlePayload._0])
            } else if let directArray = try? container.decode([String].self, forKey: .genre) {
                self = .genre(directArray)
            } else {
                let directSingle = try container.decode(String.self, forKey: .genre)
                self = .genre([directSingle])
            }
        } else if container.contains(.mediaType) {
            if let arrayPayload = try? container.decode(SingleAssociated<[MediaType]>.self, forKey: .mediaType) {
                self = .mediaType(arrayPayload._0)
            } else if let singlePayload = try? container.decode(SingleAssociated<MediaType>.self, forKey: .mediaType) {
                self = .mediaType([singlePayload._0])
            } else if let directArray = try? container.decode([MediaType].self, forKey: .mediaType) {
                self = .mediaType(directArray)
            } else {
                let directSingle = try container.decode(MediaType.self, forKey: .mediaType)
                self = .mediaType([directSingle])
            }
        } else if container.contains(.state) {
            if let arrayPayload = try? container.decode(SingleAssociated<[MediaState]>.self, forKey: .state) {
                self = .state(arrayPayload._0)
            } else if let singlePayload = try? container.decode(SingleAssociated<MediaState>.self, forKey: .state) {
                self = .state([singlePayload._0])
            } else if let directArray = try? container.decode([MediaState].self, forKey: .state) {
                self = .state(directArray)
            } else {
                let directSingle = try container.decode(MediaState.self, forKey: .state)
                self = .state([directSingle])
            }
        } else if container.contains(.taste) {
            if let arrayPayload = try? container.decode(SingleAssociated<[TasteValue]>.self, forKey: .taste) {
                self = .taste(arrayPayload._0)
            } else if let singlePayload = try? container.decode(SingleAssociated<TasteValue>.self, forKey: .taste) {
                self = .taste([singlePayload._0])
            } else if let directArray = try? container.decode([TasteValue].self, forKey: .taste) {
                self = .taste(directArray)
            } else {
                let directSingle = try container.decode(TasteValue.self, forKey: .taste)
                self = .taste([directSingle])
            }
        } else if container.contains(.badge) {
            if let arrayPayload = try? container.decode(SingleAssociated<[String]>.self, forKey: .badge) {
                self = .badge(arrayPayload._0)
            } else if let singlePayload = try? container.decode(SingleAssociated<String>.self, forKey: .badge) {
                self = .badge([singlePayload._0])
            } else if let directArray = try? container.decode([String].self, forKey: .badge) {
                self = .badge(directArray)
            } else {
                let directSingle = try container.decode(String.self, forKey: .badge)
                self = .badge([directSingle])
            }
        } else if container.contains(.network) {
            if let arrayPayload = try? container.decode(SingleAssociated<[String]>.self, forKey: .network) {
                self = .network(arrayPayload._0)
            } else if let singlePayload = try? container.decode(SingleAssociated<String>.self, forKey: .network) {
                self = .network([singlePayload._0])
            } else if let directArray = try? container.decode([String].self, forKey: .network) {
                self = .network(directArray)
            } else {
                let directSingle = try container.decode(String.self, forKey: .network)
                self = .network([directSingle])
            }
        } else if container.contains(.language) {
            if let arrayPayload = try? container.decode(SingleAssociated<[String]>.self, forKey: .language) {
                self = .language(arrayPayload._0)
            } else if let singlePayload = try? container.decode(SingleAssociated<String>.self, forKey: .language) {
                self = .language([singlePayload._0])
            } else if let directArray = try? container.decode([String].self, forKey: .language) {
                self = .language(directArray)
            } else {
                let directSingle = try container.decode(String.self, forKey: .language)
                self = .language([directSingle])
            }
        } else if container.contains(.releaseYear) {
            let pair = try container.decode(DoubleAssociated<Int, Comparison>.self, forKey: .releaseYear)
            self = .releaseYear(pair._0, pair._1)
        } else if container.contains(.releaseYearRange) {
            let pair = try container.decode(DoubleAssociated<Int, Int>.self, forKey: .releaseYearRange)
            self = .releaseYearRange(pair._0, pair._1)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown SmartRule case")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .genre(let g):
            try container.encode(SingleAssociated(_0: g), forKey: .genre)
        case .mediaType(let t):
            try container.encode(SingleAssociated(_0: t), forKey: .mediaType)
        case .state(let s):
            try container.encode(SingleAssociated(_0: s), forKey: .state)
        case .taste(let t):
            try container.encode(SingleAssociated(_0: t), forKey: .taste)
        case .badge(let b):
            try container.encode(SingleAssociated(_0: b), forKey: .badge)
        case .network(let n):
            try container.encode(SingleAssociated(_0: n), forKey: .network)
        case .language(let l):
            try container.encode(SingleAssociated(_0: l), forKey: .language)
        case .releaseYear(let year, let comp):
            try container.encode(DoubleAssociated(_0: year, _1: comp), forKey: .releaseYear)
        case .releaseYearRange(let start, let end):
            try container.encode(DoubleAssociated(_0: start, _1: end), forKey: .releaseYearRange)
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
