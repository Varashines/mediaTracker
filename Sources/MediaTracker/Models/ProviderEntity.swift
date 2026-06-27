import Foundation
import SwiftData

@Model
final class ProviderEntity {
    @Attribute(.unique) var providerID: Int
    var name: String
    var logoPath: String?
    var count: Int
    
    init(providerID: Int, name: String, logoPath: String?, count: Int = 0) {
        self.providerID = providerID
        self.name = name
        self.logoPath = logoPath
        self.count = count
    }
}
