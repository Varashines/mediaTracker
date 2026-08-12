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
    /// Weight for a disliked season in the per-season taste model. 0 = neutral
    /// (a hated season neither rewards nor penalizes the actors in it). Set to
    /// -1 to actively subtract actors present in seasons you dislike.
    static let dislikedSeasonWeight: Double = 0

    /// Whole-title weight tier so longer shows count more than movies/short shows
    /// in genre/network/creator affinity. Movie = 1; show by season count:
    /// 0-2 → 1, 3-6 → 2, 7+ → 3.
    static func titleWeight(seasonCount: Int) -> Int {
        switch seasonCount {
        case 3...6: return 2
        case 7...:  return 3
        default:    return 1
        }
    }

    /// Per-season taste weight: Loved = 2, Liked = 1, Disliked = dislikedSeasonWeight,
    /// None/empty = 0.
    static func seasonWeight(_ tasteValue: String?) -> Double {
        guard let tasteValue, let taste = TasteValue(rawValue: tasteValue) else { return 0 }
        switch taste {
        case .love:    return 2
        case .like:    return 1
        case .dislike: return dislikedSeasonWeight
        case .none:    return 0
        }
    }

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
