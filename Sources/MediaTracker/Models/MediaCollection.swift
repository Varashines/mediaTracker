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

    /// Complete smart configuration — rules plus All/Any match mode. Stored as a
    /// `SmartRuleSet` JSON blob; falls back to the legacy `[SmartRule]` array
    /// format (All mode) so pre-wrapper libraries and backups keep decoding.
    var smartRuleSet: SmartRuleSet {
        get {
            guard let data = smartRulesData, !data.isEmpty else { return SmartRuleSet() }
            if let set = try? JSONDecoder().decode(SmartRuleSet.self, from: data) {
                return set
            }
            if let legacy = try? JSONDecoder().decode([SmartRule].self, from: data) {
                return SmartRuleSet(matchAny: false, rules: legacy)
            }
            // Never silently degrade to match-everything without a trace.
            AppLogger.warning("Smart rules for '\(name)' failed to decode — resetting to empty", logger: AppLogger.data)
            return SmartRuleSet()
        }
        set {
            smartRulesData = try? JSONEncoder().encode(newValue)
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
