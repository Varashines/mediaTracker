import Foundation
import SwiftData

@Model
final class MediaCollection: Identifiable {
    var id: UUID
    var name: String
    var systemImage: String
    var completedItemIDs: [String] = []
    var notes: String? = ""
    var isPinned: Bool = false
    
    var smartRulesData: Data?
    
    var isSmart: Bool { smartRulesData != nil }
    
    @Relationship(inverse: \MediaItem.collections)
    var items: [MediaItem]
    
    init(id: UUID = UUID(), name: String, systemImage: String, isSmart: Bool = false) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.items = []
        if isSmart { smartRulesData = Data() }
    }
    
    var smartRules: [SmartRule] {
        get { smartRuleSet.rules }
        set {
            var set = smartRuleSet
            set.rules = newValue
            smartRuleSet = set
        }
    }

    @Transient private var cachedRuleSet: (dataHash: Int, ruleSet: SmartRuleSet)?

    /// Complete smart configuration — rules plus All/Any match mode. Stored as a
    /// `SmartRuleSet` JSON blob; falls back to the legacy `[SmartRule]` array
    /// format (All mode) so pre-wrapper libraries and backups keep decoding.
    var smartRuleSet: SmartRuleSet {
        get {
            guard let data = smartRulesData, !data.isEmpty else { return SmartRuleSet() }
            let hash = data.hashValue
            if let cached = cachedRuleSet, cached.dataHash == hash {
                return cached.ruleSet
            }
            let decoded: SmartRuleSet
            if let set = try? JSONDecoder().decode(SmartRuleSet.self, from: data) {
                decoded = set
            } else if let legacy = try? JSONDecoder().decode([SmartRule].self, from: data) {
                decoded = SmartRuleSet(matchAny: false, rules: legacy)
            } else {
                // Never silently degrade to match-everything without a trace.
                AppLogger.warning("Smart rules for '\(name)' failed to decode — resetting to empty", logger: AppLogger.data)
                decoded = SmartRuleSet()
            }
            cachedRuleSet = (hash, decoded)
            return decoded
        }
        set {
            let encoded = try? JSONEncoder().encode(newValue)
            smartRulesData = encoded
            if let encoded {
                cachedRuleSet = (encoded.hashValue, newValue)
            } else {
                cachedRuleSet = nil
            }
        }
    }

    var smartMatchAny: Bool {
        get { smartRuleSet.matchAny }
        set {
            var set = smartRuleSet
            set.matchAny = newValue
            smartRuleSet = set
        }
    }
}
