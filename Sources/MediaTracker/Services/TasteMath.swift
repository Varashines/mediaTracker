import Foundation
import SwiftData

struct CategoryStats: Sendable {
    var loved = 0
    var liked = 0
    var disliked = 0
    var total = 0
    /// Number of distinct rated titles (unweighted). Used as the qualification
    /// cutoff so weighted affinity points never inflate the "how many titles"
    /// requirement.
    var ratedTitles = 0
    var profileURL: String? = nil

    var ratedCount: Int { loved + liked + disliked }

    func affinity(cutoff: Int = 5, belowCutoffValue: Double = 0) -> Double {
        guard ratedTitles >= cutoff else { return belowCutoffValue }
        // Bayesian-smoothed taste score (prior 0.5, strength 5):
        // Loved = 1.0, Liked = 0.5, Disliked = 0. Small samples regress toward
        // the neutral prior so a few perfect ratings don't outrank larger libraries.
        let sum = Double(loved) + 0.5 * Double(liked)
        return (sum + 2.5) / (Double(ratedCount) + 5.0)
    }
}

enum TasteMath {
    static func updateTaste(_ map: inout [String: CategoryStats], _ key: String, _ taste: String, profileURL: String? = nil, weight: Int = 1) {
        var s = map[key, default: CategoryStats()]
        s.total += 1
        if let tasteVal = TasteValue(rawValue: taste) {
            switch tasteVal {
            case .love: s.loved += weight
            case .like: s.liked += weight
            case .dislike: s.disliked += weight
            case .none: break
            }
            if tasteVal != .none { s.ratedTitles += 1 }
        }
        if let url = profileURL { s.profileURL = url }
        map[key] = s
    }

    /// Rank comparator: affinity score (desc), then title count (desc), then
    /// alphabetical (case-insensitive). Used for Hall of Fame and taste rankings.
    static func compareByAffinityCountName(
        _ a: (score: Double, count: Int, name: String),
        _ b: (score: Double, count: Int, name: String)
    ) -> Bool {
        if a.score != b.score { return a.score > b.score }
        if a.count != b.count { return a.count > b.count }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}
