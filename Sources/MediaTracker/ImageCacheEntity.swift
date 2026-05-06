import Foundation
import SwiftData

/// Represents a cached image blob in the SQLite database to avoid file system clutter.
@Model
final class ImageCacheEntity {
    @Attribute(.unique) var id: String
    var data: Data
    var accessDate: Date
    var size: Int64
    
    init(id: String, data: Data, accessDate: Date, size: Int64) {
        self.id = id
        self.data = data
        self.accessDate = accessDate
        self.size = size
    }
}
