import Foundation

struct DiscoveryFilter: Hashable, Codable {
    let type: FilterType
    let name: String
    var sourceNames: [String]? = nil
}

struct SimpleCastMember: Codable, Identifiable {
    let id: String
    let name: String
    let characterName: String
    let profileURL: String?
    let order: Int
}

struct DiscoveryNode: Identifiable, Equatable, Codable {
    var id: String { code ?? name }
    let name: String
    var code: String? = nil
    let logoPath: String?
    let count: Int
    var themeColorHex: String? = nil
    var sourceNames: [String]? = nil
}
