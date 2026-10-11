import Foundation
import SwiftData

@Model
final class ProviderEntity {
    @Attribute(.unique) var name: String
    var providerID: Int
    var logoPath: String?
    var count: Int
    
    init(name: String, providerID: Int = 0, logoPath: String? = nil, count: Int = 0) {
        self.name = name
        self.providerID = providerID
        self.logoPath = logoPath
        self.count = count
    }
}
