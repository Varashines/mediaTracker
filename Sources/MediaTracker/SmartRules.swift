import Foundation

enum SmartRule: Codable, Equatable {
    case genre(String)
    case releaseYear(Int, Comparison)
    case releaseYearRange(Int, Int)
    case mediaType(MediaType)
    case state(MediaState)
    case taste(TasteValue)
    
    enum Comparison: String, Codable {
        case equals = "is"
        case after = "after"
        case before = "before"
    }
}
