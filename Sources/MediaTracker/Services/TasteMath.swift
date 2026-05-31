import Foundation
import SwiftData

struct CategoryStats: Sendable {
    var loved = 0
    var liked = 0
    var disliked = 0
    var total = 0
    var profileURL: String? = nil

    var ratedCount: Int { loved + liked + disliked }

    func affinity(cutoff: Int = 5, belowCutoffValue: Double = 0) -> Double {
        guard ratedCount >= cutoff else { return belowCutoffValue }
        let lovedWeight = Double(3 * loved)
        let likedWeight = Double(liked)
        let dislikedWeight = Double(2 * disliked)
        let totalWeight = Double(3 * ratedCount)
        let score = (lovedWeight + likedWeight - dislikedWeight) / totalWeight
        return max(0, score)
    }
}

enum TasteMath {
    static func updateTaste(_ map: inout [String: CategoryStats], _ key: String, _ taste: String, profileURL: String? = nil) {
        var s = map[key, default: CategoryStats()]
        s.total += 1
        if let tasteVal = TasteValue(rawValue: taste) {
            switch tasteVal {
            case .love: s.loved += 1
            case .like: s.liked += 1
            case .dislike: s.disliked += 1
            case .none: break
            }
        }
        if let url = profileURL { s.profileURL = url }
        map[key] = s
    }
}
