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

    /// Single source of truth for a season's effective taste: a manual override
    /// always wins; otherwise the show's taste is inherited only for fully
    /// watched seasons. Used by both the UI and the affinity scoring.
    static func effectiveSeasonTasteRaw(override: String?, isFullyWatched: Bool, showTaste: String?) -> String? {
        if let override { return override }
        guard isFullyWatched else { return nil }
        return showTaste
    }

    /// Weight for a title: 1 for movies, else the season-count tier for TV.
    static func titleWeight(for item: MediaItem) -> Int {
        titleWeight(seasonCount: item.type == .tvShow ? item.cachedSeasonCount : 0)
    }

    /// Shared genre accumulation so the aggregation actors don't hand-roll it.
    static func accumulateGenres(_ map: inout [String: CategoryStats], genres: [String], taste: String, weight: Int) {
        for g in genres { updateTaste(&map, g, taste, weight: weight) }
    }

    /// Shared top-billed cast accumulation (used by the non-season aggregation
    /// paths). Season-based cast scoring lives separately in TasteActor.
    static func accumulateTopBilledCast(_ map: inout [String: CategoryStats], cast: [SimpleCastMember], taste: String, limit: Int, weight: Int) {
        for actor in cast.prefix(limit) {
            updateTaste(&map, actor.name, taste, profileURL: actor.profileURL, weight: weight)
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
