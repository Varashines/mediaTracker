import Foundation
import SwiftData

struct TasteProfile: Sendable {
    let topGenres: [String: Double]
    let topNetworks: [String: Double]
    let topDirectors: [String: Double]
}

struct TasteInsights: Sendable {
    let genreAffinities: [(name: String, affinity: Double)]
    let creatorAffinities: [(name: String, affinity: Double, imageURL: String?)]
    let castAffinities: [(name: String, affinity: Double, imageURL: String?)]
    let languageAffinities: [(name: String, affinity: Double)]
}

@ModelActor
actor TasteActor {
    // Phase 3 Optimization: Cache affinity maps to prevent redundant full-library scans
    // Using static storage because the actor is instantiated ephemerally to prevent ModelContext leaks.
    @MainActor private static var cachedAffinityMap: (
        genre: [String: Double], network: [String: Double], cast: [String: Double],
        creator: [String: Double], language: [String: Double]
    )?
    @MainActor private static var lastAffinityCalculation: Date?
    private let affinityCacheTTL: TimeInterval = .secondsInDay

    @MainActor private static var cachedRecommendations: [(id: PersistentIdentifier, reason: String)]?
    @MainActor private static var lastRecommendationsCache: Date?
    private let recommendationsCacheTTL: TimeInterval = 300 // 5 minutes

    @MainActor static func clearCache() {
        cachedAffinityMap = nil
        lastAffinityCalculation = nil
        cachedRecommendations = nil
        lastRecommendationsCache = nil
    }

    func fetchTasteInsights() async -> TasteInsights {
        let profile = await calculateAffinityMaps()

        let sortedGenres = profile.genre.map { ($0.key, $0.value) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }

        let creatorResults = await resolveAffinities(profile.creator, cutoff: 0)
        let castResults = await resolveAffinities(profile.cast, cutoff: 0)

        let sortedLangs = profile.language.map {
            (LanguageUtils.languageName(for: $0.key), $0.value)
        }
        .filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }

        return TasteInsights(
            genreAffinities: sortedGenres,
            creatorAffinities: creatorResults,
            castAffinities: castResults,
            languageAffinities: sortedLangs
        )
    }

    private func resolveAffinities(_ map: [String: Double], cutoff: Double) async -> [(name: String, affinity: Double, imageURL: String?)] {
        let top = map.map { ($0.key, $0.value) }
            .filter { $0.1 > cutoff }
            .sorted { $0.1 > $1.1 }
            .prefix(10)

        var results: [(name: String, affinity: Double, imageURL: String?)] = []
        for (name, affinity) in top {
            let image = await resolvePersonImage(for: name)
            results.append((name, affinity, image))
        }
        return results
    }

    private func resolvePersonImage(for name: String) async -> String? {
        let cacheDescriptor = FetchDescriptor<PersonImageEntity>(
            predicate: #Predicate { $0.name == name })
        if let cached = try? modelContext.fetch(cacheDescriptor).first {
            return cached.profileURL
        }

        let castDescriptor = FetchDescriptor<CastMember>(predicate: #Predicate { $0.name == name })
        if let member = try? modelContext.fetch(castDescriptor).first(where: { $0.profileURL != nil }) {
            let url = member.profileURL
            modelContext.insert(PersonImageEntity(name: name, profileURL: url))
            return url
        }

        return nil
    }

    private func calculateAffinityMaps() async -> (
        genre: [String: Double], network: [String: Double], cast: [String: Double],
        creator: [String: Double], language: [String: Double]
    ) {
        if await SleepManager.shared.isAsleep { return ([:], [:], [:], [:], [:]) }

        let (cached, last) = await MainActor.run { (Self.cachedAffinityMap, Self.lastAffinityCalculation) }
        if let cached = cached, let last = last, Date().timeIntervalSince(last) < affinityCacheTTL {
            return cached
        }

        var accumulators = AffinityAccumulators()
        let lookups = await buildSeasonLookups()

        let batchSize = 500
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.tasteValue != "None" })
            descriptor.propertiesToFetch = [
                \.id, \.title,
                \.typeValue, \.stateValue, \.tasteValue,
                \.cachedGenres, \.cachedLanguage, \.cachedNetwork, \.cachedCreators,
                \.storedCast, \.cachedSeasonCount
            ]
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            
            guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { break }
            accumulateBatch(items, into: &accumulators, lookups: lookups)
            
            offset += batchSize
        }

        let result = finalizeAffinities(accumulators)

        await MainActor.run {
            Self.cachedAffinityMap = result
            Self.lastAffinityCalculation = Date()
        }
        return result
    }

    /// Pre-fetch per-season cast and season taste overrides once per affinity
    /// calculation, keyed by show id, so the hot accumulation loop avoids
    /// relationship faults.
    private func buildSeasonLookups() async -> SeasonLookups {
        var lookups = SeasonLookups()

        var seasonCastDesc = FetchDescriptor<SeasonCastMember>(predicate: #Predicate { $0.episodeCount > 0 })
        seasonCastDesc.propertiesToFetch = [
            \.showID, \.seasonNumber, \.name, \.tmdbPersonID, \.episodeCount
        ]
        if let allSeasonCast = try? modelContext.fetch(seasonCastDesc) {
            for sc in allSeasonCast where sc.qualifiesForTaste && sc.seasonNumber > 0 {
                lookups.castByShow[sc.showID, default: []].append(sc)
            }
        }

        // Fetch all seasons once: overrides AND watched status (inheritance of
        // the show's taste only applies to fully watched seasons).
        var seasonDesc = FetchDescriptor<TVSeason>(predicate: #Predicate { $0.showID != nil })
        seasonDesc.propertiesToFetch = [\.showID, \.seasonNumber, \.tasteOverrideRaw, \.watchedEpisodesCount, \.totalEpisodesCount, \.episodeCount]
        if let allSeasons = try? modelContext.fetch(seasonDesc) {
            for s in allSeasons {
                guard let sid = s.showID else { continue }
                if let ov = s.tasteOverrideRaw {
                    lookups.overrideByShowSeason[sid, default: [:]][s.seasonNumber] = ov
                }
                if s.isFullyWatched {
                    lookups.watchedByShowSeason[sid, default: []].insert(s.seasonNumber)
                }
            }
        }
        return lookups
    }

    private struct SeasonLookups {
        var castByShow: [Int: [SeasonCastMember]] = [:]
        var overrideByShowSeason: [Int: [Int: String]] = [:]
        var watchedByShowSeason: [Int: Set<Int>] = [:]
    }

    /// Extracts the TMDb id from a MediaItem id ("tv_1418" -> 1418). Movies have
    /// no tv_ prefix and return nil (they don't use season-based cast scoring).
    private nonisolated static func tmdbID(from id: String) -> Int? {
        guard id.hasPrefix("tv_") else { return nil }
        return Int(id.dropFirst(3))
    }

    struct ActorStats: Sendable {
        var loved: Double = 0
        var liked: Double = 0
        var disliked: Double = 0
        var total: Int = 0
        var leadCount: Int = 0

        func affinity() -> Double {
            let netPoints = loved + 0.5 * liked - 0.75 * disliked
            guard netPoints > 0 else { return 0.0 }
            let ratio = (netPoints + 2.0) / (Double(total) + 3.0)
            let volumeBonus = log(loved + 2.0) / log(4.0)
            return ratio * volumeBonus
        }
    }

    private struct AffinityAccumulators {
        var genreStats: [String: CategoryStats] = [:]
        var networkStats: [String: CategoryStats] = [:]
        var actorStats: [String: ActorStats] = [:]
        var creatorStats: [String: CategoryStats] = [:]
        var languageStats: [String: CategoryStats] = [:]
    }

    private func accumulateBatch(_ items: [MediaItem], into acc: inout AffinityAccumulators, lookups: SeasonLookups) {
        for item in items {
            let taste = item.tasteValue
            let titleWeight = TasteMath.titleWeight(for: item)

            TasteMath.accumulateGenres(&acc.genreStats, genres: item.cachedGenres, taste: taste, weight: titleWeight)
            if let rawNetwork = item.cachedNetwork {
                for n in rawNetwork.commaSeparatedValues where !n.isEmpty {
                    TasteMath.updateTaste(&acc.networkStats, n, taste, weight: titleWeight)
                }
            }
            if let l = item.cachedLanguage { TasteMath.updateTaste(&acc.languageStats, l, taste, weight: titleWeight) }
            for creator in item.cachedCreators { TasteMath.updateTaste(&acc.creatorStats, creator, taste, weight: titleWeight) }

            // Cast affinity: per-season when season-cast data exists, else top-billed fallback.
            if item.type == .tvShow, let tmdbID = Self.tmdbID(from: item.id),
               let members = lookups.castByShow[tmdbID], !members.isEmpty {
                for m in members {
                    let isFullyWatched = lookups.watchedByShowSeason[tmdbID]?.contains(m.seasonNumber) == true
                    let effective = TasteMath.effectiveSeasonTasteRaw(
                        override: lookups.overrideByShowSeason[tmdbID]?[m.seasonNumber],
                        isFullyWatched: isFullyWatched,
                        showTaste: taste
                    )
                    guard let effective else { continue }
                    var s = acc.actorStats[m.name, default: ActorStats()]
                    s.total += 1
                    if effective == "Love" { s.loved += 1.0 }
                    else if effective == "Like" { s.liked += 0.6 }
                    else if effective == "Dislike" { s.disliked += 0.6 }
                    acc.actorStats[m.name] = s
                }
            } else {
                let limit = item.type == .movie ? 5 : 10
                for (idx, actor) in item.displayCast.prefix(limit).enumerated() {
                    let leadMult = idx == 0 ? 1.0 : 0.6
                    var s = acc.actorStats[actor.name, default: ActorStats()]
                    s.total += 1
                    if idx == 0 { s.leadCount += 1 }
                    if taste == "Love" { s.loved += leadMult }
                    else if taste == "Like" { s.liked += leadMult }
                    else if taste == "Dislike" { s.disliked += leadMult }
                    acc.actorStats[actor.name] = s
                }
            }
        }
    }

    private func finalizeAffinities(_ acc: AffinityAccumulators) -> (
        genre: [String: Double], network: [String: Double], cast: [String: Double],
        creator: [String: Double], language: [String: Double]
    ) {
        return (
            acc.genreStats.mapValues { $0.affinity(cutoff: 5) },
            acc.networkStats.mapValues { $0.affinity(cutoff: 5) },
            acc.actorStats.mapValues { $0.affinity() },
            acc.creatorStats.mapValues { $0.creatorAffinity() },
            acc.languageStats.mapValues { $0.affinity(cutoff: 5) }
        )
    }

    func calculateRecommendations() async -> [(id: PersistentIdentifier, reason: String)] {
        // Return cached recommendations if fresh enough
        let (cached, last) = await MainActor.run { (Self.cachedRecommendations, Self.lastRecommendationsCache) }
        if let cached = cached, let last = last, Date().timeIntervalSince(last) < recommendationsCacheTTL {
            return cached
        }

        // Fetch Weights from UserDefaults (matches AppStorage keys in UI)
        func weight(_ key: UserDefaultsKeys, default defaultVal: Double) -> Double {
            let val = UserDefaults.standard.double(forKey: key.rawValue)
            return val == 0 ? defaultVal : val
        }
        let wGenre = weight(.tasteWeightGenre, default: 15.0)
        let wCreator = weight(.tasteWeightCreator, default: 20.0)
        let wCast = weight(.tasteWeightCast, default: 15.0)
        let wNetwork = weight(.tasteWeightNetwork, default: 5.0)
        let wLang = weight(.tasteWeightLang, default: 10.0)
        let weightSum = wGenre + wCreator + wCast + wNetwork + wLang

        let profile = await calculateAffinityMaps()
        let genreAffinity = profile.genre
        let networkAffinity = profile.network
        let castAffinity = profile.cast
        let creatorAffinity = profile.creator
        let langAffinity = profile.language

        var descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.stateValue == "Wishlist" })
        descriptor.propertiesToFetch = [
            \.id, \.title, \.releaseDate,
            \.typeValue, \.stateValue, \.tasteValue,
            \.cachedGenres, \.cachedLanguage, \.cachedNetwork, \.cachedCreators,
            \.cachedNextAiringDate, \.storedCast
        ]
        guard let wishlist = try? modelContext.fetch(descriptor) else { return [] }
        var recommendations: [(id: PersistentIdentifier, score: Double, reason: String)] = []
        let now = Date()

        for item in wishlist {
            guard let targetDate = item.cachedNextAiringDate ?? item.releaseDate else {
                continue
            }

            // 1. Cast Matching (All-Star Ensemble Power)
            var castPower: Double = 0
            var castMatches: [(name: String, aff: Double, idx: Int)] = []
            let limit = item.type == .movie ? 5 : 10
            let itemCast = item.displayCast.prefix(limit).map { $0.name }
            for (idx, actor) in itemCast.enumerated() {
                if let aff = castAffinity[actor], aff > 0 {
                    let decay = idx == 0 ? 1.0 : (idx == 1 ? 0.5 : 0.25)
                    castPower += (aff * decay)
                    castMatches.append((actor, aff, idx))
                }
            }
            let castFit = min(1.25, castPower)

            // 2. Director / Creator Matching
            var dirFit: Double = 0.5
            var topCreator: String? = nil
            for creator in item.cachedCreators {
                if let aff = creatorAffinity[creator], aff > 0 {
                    if aff > dirFit {
                        dirFit = aff
                        topCreator = creator
                    }
                }
            }

            // 3. Genre Matching
            let gAffs = item.cachedGenres.compactMap { genreAffinity[$0] }
            let genreFit = gAffs.isEmpty ? 0.5 : (gAffs.reduce(0, +) / Double(item.cachedGenres.count))
            let topGenre = item.cachedGenres.max(by: { (genreAffinity[$0] ?? 0) < (genreAffinity[$1] ?? 0) })

            // 4. Network / Studio & Language Matching
            let nList = item.cachedNetwork?.commaSeparatedValues ?? []
            let nAffs = nList.compactMap { networkAffinity[$0] }
            let networkFit = nAffs.isEmpty ? 0.5 : (nAffs.max() ?? 0.5)
            let topNetwork = nList.first
            let langFit = item.cachedLanguage.flatMap { langAffinity[$0] } ?? 0.5

            // Base Multi-Dimensional Fit
            let baseFit = ((wCast / weightSum) * castFit)
                + ((wCreator / weightSum) * dirFit)
                + ((wGenre / weightSum) * genreFit)
                + ((wNetwork / weightSum) * networkFit)
                + ((wLang / weightSum) * langFit)

            // Multiplicative Synergy Multiplier
            var synergy = 1.0
            if networkFit > 0.70 && castFit > 0.80 { synergy += 0.15 }
            if dirFit > 0.65 && castFit > 0.70 { synergy += 0.10 }
            if dirFit > 0.65 && genreFit > 0.75 { synergy += 0.05 }

            // Asymmetric Availability & Hype Decay
            let timeDifference = targetDate.timeIntervalSince(now)
            let days = timeDifference / .secondsInDay
            let timeDecay: Double = {
                if days >= 0 {
                    return 1.0 / (1.0 + 0.0012 * days)
                } else {
                    return 1.0 / (1.0 + 0.0015 * abs(days))
                }
            }()

            let finalScore = baseFit * synergy * timeDecay * 100.0

            if finalScore > 0 {
                var potentialReasons: [(label: String, score: Double)] = []
                if let leadActor = castMatches.first, leadActor.aff > 0.65 {
                    let mult = leadActor.idx == 0 ? 1.25 : 0.85
                    potentialReasons.append(("Starring \(leadActor.name)", leadActor.aff * mult * (wCast / 15.0)))
                }
                if let topCreator, dirFit > 0.65 {
                    let prefix = item.type == .movie ? "Directed by" : "Created by"
                    potentialReasons.append(("\(prefix) \(topCreator)", dirFit * 1.15 * (wCreator / 20.0)))
                }
                if let topNetwork, networkFit > 0.75 {
                    potentialReasons.append(("From \(topNetwork)", networkFit * 1.10 * (wNetwork / 5.0)))
                }
                if let topGenre, let gAff = genreAffinity[topGenre], gAff > 0.75 {
                    potentialReasons.append(("Because you love \(topGenre)", gAff * 0.95 * (wGenre / 15.0)))
                }

                let bestReason = potentialReasons.max(by: { $0.score < $1.score })?.label ?? "Picked for your taste"
                recommendations.append((item.persistentModelID, finalScore, bestReason))
            }
        }

        let result = recommendations.sorted { $0.score > $1.score }.prefix(10).map { ($0.id, $0.reason) }
        await MainActor.run {
            Self.cachedRecommendations = result
            Self.lastRecommendationsCache = Date()
        }
        return result
    }
}
