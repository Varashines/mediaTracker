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
        get {
            guard let data = smartRulesData else { return [] }
            return (try? JSONDecoder().decode([SmartRule].self, from: data)) ?? []
        }
        set {
            smartRulesData = try? JSONEncoder().encode(newValue)
        }
    }
}
