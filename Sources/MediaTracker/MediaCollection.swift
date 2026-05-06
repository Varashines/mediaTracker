import Foundation
import SwiftData

@Model
final class MediaCollection: Identifiable {
    var id: UUID
    var name: String
    var systemImage: String
    var completedItemIDs: [String] = []
    
    @Relationship(inverse: \MediaItem.collections)
    var items: [MediaItem]
    
    init(id: UUID = UUID(), name: String, systemImage: String) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.items = []
    }
}
