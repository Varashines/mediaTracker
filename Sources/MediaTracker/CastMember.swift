import Foundation
import SwiftData

@Model
final class CastMember {
    var uniqueID: String?
    var mediaID: String?
    var name: String
    var characterName: String
    var profileURL: String?
    var order: Int
    var movieDetails: MovieDetails?
    var tvShowDetails: TVShowDetails?

    init(name: String, characterName: String, profileURL: String? = nil, order: Int = 0, mediaID: String? = nil) {
        self.name = name
        self.characterName = characterName
        self.profileURL = profileURL
        self.order = order
        self.mediaID = mediaID
        if let mID = mediaID {
            self.uniqueID = "\(mID)_\(name)_\(characterName)"
        } else {
            self.uniqueID = UUID().uuidString
        }
    }
}
