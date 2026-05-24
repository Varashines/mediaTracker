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
    private let affinityCacheTTL: TimeInterval = 86400 // 24 hours

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
        // 1. Check local Cache Entity
        let cacheDescriptor = FetchDescriptor<PersonImageEntity>(
            predicate: #Predicate { $0.name == name })
        if let cached = try? modelContext.fetch(cacheDescriptor).first {
            return cached.profileURL
        }

        // 2. Check Library CastMembers
        let castDescriptor = FetchDescriptor<CastMember>(predicate: #Predicate { $0.name == name })
        if let member = try? modelContext.fetch(castDescriptor).first(where: {
            $0.profileURL != nil
        }) {
            let url = member.profileURL
            // Save to cache for next time
            modelContext.insert(PersonImageEntity(name: name, profileURL: url))
            return url
        }

        // 2. On-Demand API Search
        if let path = try? await APIClient.shared.searchPerson(query: name) {
            let fullURL = APIClient.tmdbImageURL(path: path, size: "w185") ?? ""
            modelContext.insert(PersonImageEntity(name: name, profileURL: fullURL))
            try? modelContext.save()
            return fullURL
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

        let batchSize = 500
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.tasteValue != "None" })
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            
            guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { break }
            accumulateBatch(items, into: &accumulators)
            
            offset += batchSize
        }

        let result = finalizeAffinities(accumulators)

        await MainActor.run {
            Self.cachedAffinityMap = result
            Self.lastAffinityCalculation = Date()
        }
        return result
    }

    private struct CategoryStats {
        var loved = 0
        var liked = 0
        var disliked = 0
        var total = 0
        func affinity(cutoff: Int = 5) -> Double {
            guard total >= cutoff else { return 0 }
            let lovedWeight = Double(3 * loved)
            let likedWeight = Double(liked)
            let dislikedWeight = Double(2 * disliked)
            let totalWeight = Double(3 * total)
            return (lovedWeight + likedWeight - dislikedWeight) / totalWeight
        }
    }

    private struct AffinityAccumulators {
        var genreStats: [String: CategoryStats] = [:]
        var networkStats: [String: CategoryStats] = [:]
        var castStats: [String: CategoryStats] = [:]
        var creatorStats: [String: CategoryStats] = [:]
        var languageStats: [String: CategoryStats] = [:]
    }

    private func updateTaste(_ map: inout [String: CategoryStats], _ key: String, _ taste: String) {
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
        map[key] = s
    }

    private func accumulateBatch(_ items: [MediaItem], into acc: inout AffinityAccumulators) {
        for item in items {
            let taste = item.tasteValue
            for g in item.cachedGenres { updateTaste(&acc.genreStats, g, taste) }
            if let rawNetwork = item.cachedNetwork {
                let networks = rawNetwork.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                for n in networks where !n.isEmpty {
                    updateTaste(&acc.networkStats, n, taste)
                }
            }
            if let l = item.cachedLanguage { updateTaste(&acc.languageStats, l, taste) }

            let limit = item.type == .movie ? 5 : 10
            let cast = item.displayCast.prefix(limit).map { $0.name }
            for actor in cast { updateTaste(&acc.castStats, actor, taste) }
            // Use the denormalized cachedCreators to avoid faulting movieDetails/tvShowDetails relationships
            for creator in item.cachedCreators { updateTaste(&acc.creatorStats, creator, taste) }
        }
    }

    private func finalizeAffinities(_ acc: AffinityAccumulators) -> (
        genre: [String: Double], network: [String: Double], cast: [String: Double],
        creator: [String: Double], language: [String: Double]
    ) {
        return (
            acc.genreStats.mapValues { $0.affinity(cutoff: 5) },
            acc.networkStats.mapValues { $0.affinity(cutoff: 5) },
            acc.castStats.mapValues { $0.affinity(cutoff: 5) },
            acc.creatorStats.mapValues { $0.affinity(cutoff: 3) },
            acc.languageStats.mapValues { $0.affinity(cutoff: 5) }
        )
    }

    func calculateRecommendations() async -> [(id: PersistentIdentifier, reason: String)] {
        // Fetch Weights from UserDefaults (matches AppStorage keys in UI)
        let wGenre =
            UserDefaults.standard.double(forKey: UserDefaultsKeys.tasteWeightGenre.rawValue) == 0
            ? 15.0 : UserDefaults.standard.double(forKey: UserDefaultsKeys.tasteWeightGenre.rawValue)
        let wCreator =
            UserDefaults.standard.double(forKey: UserDefaultsKeys.tasteWeightCreator.rawValue) == 0
            ? 20.0 : UserDefaults.standard.double(forKey: UserDefaultsKeys.tasteWeightCreator.rawValue)
        let wCast =
            UserDefaults.standard.double(forKey: UserDefaultsKeys.tasteWeightCast.rawValue) == 0
            ? 15.0 : UserDefaults.standard.double(forKey: UserDefaultsKeys.tasteWeightCast.rawValue)
        let wNetwork =
            UserDefaults.standard.double(forKey: UserDefaultsKeys.tasteWeightNetwork.rawValue) == 0
            ? 5.0 : UserDefaults.standard.double(forKey: UserDefaultsKeys.tasteWeightNetwork.rawValue)
        let wLang =
            UserDefaults.standard.double(forKey: UserDefaultsKeys.tasteWeightLang.rawValue) == 0
            ? 10.0 : UserDefaults.standard.double(forKey: UserDefaultsKeys.tasteWeightLang.rawValue)

        let profile = await calculateAffinityMaps()
        let genreAffinity = profile.genre
        let networkAffinity = profile.network
        let castAffinity = profile.cast
        let creatorAffinity = profile.creator
        let langAffinity = profile.language

        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.stateValue == "Wishlist" })
        guard let wishlist = try? modelContext.fetch(descriptor) else { return [] }
        var recommendations: [(id: PersistentIdentifier, score: Double, reason: String)] = []
        let now = Date()

        for item in wishlist {
            var potentialReasons: [(String, Double, Int)] = []  // Label, Affinity, Priority (0=Genre, 1=Creator, 2=Other)

            // Genre matching
            var genreTotalAffinity: Double = 0
            for g in item.cachedGenres {
                if let aff = genreAffinity[g], aff != 0 {
                    genreTotalAffinity += aff
                    potentialReasons.append(("Because you like \(g)", aff, 0))
                }
            }
            let genreAverageAffinity =
                item.cachedGenres.isEmpty
                ? 0 : (genreTotalAffinity / Double(item.cachedGenres.count))

            // Network matching
            var networkAff: Double = 0
            if let rawNetwork = item.cachedNetwork {
                let networks = rawNetwork.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                var totalAff: Double = 0
                var matchedCount = 0
                for n in networks where !n.isEmpty {
                    if let aff = networkAffinity[n], aff != 0 {
                        totalAff += aff
                        matchedCount += 1
                        potentialReasons.append(("From \(n)", aff, 2))
                    }
                }
                if matchedCount > 0 {
                    networkAff = totalAff / Double(matchedCount)
                }
            }

            // Language matching
            var langAff: Double = 0
            if let l = item.cachedLanguage, let aff = langAffinity[l], aff != 0 {
                langAff = aff
                potentialReasons.append(("In \(l)", aff, 3))
            }

            // Cast matching (Reduced Weight with Decay)
            var castTotalAffinity: Double = 0
            let limit = item.type == .movie ? 5 : 10
            let itemCast = item.displayCast.prefix(limit).map { $0.name }
            for (idx, actor) in itemCast.enumerated() {
                if let aff = castAffinity[actor], aff != 0 {
                    let decay = idx < 1 ? 1.0 : 0.5
                    castTotalAffinity += (aff * decay)
                    potentialReasons.append(("Starring \(actor)", aff, 2))
                }
            }

            // Creator matching
            var creatorTotalAffinity: Double = 0
            // Use the denormalized cachedCreators to avoid faulting movieDetails/tvShowDetails relationships
            for creator in item.cachedCreators {
                if let aff = creatorAffinity[creator], aff != 0 {
                    creatorTotalAffinity += aff
                    potentialReasons.append(
                        ("\(item.type == .movie ? "Directed by" : "Created by") \(creator)", aff, 1)
                    )
                }
            }

            let totalScore =
                (genreAverageAffinity * wGenre) + (networkAff * wNetwork)
                + (castTotalAffinity * wCast) + (creatorTotalAffinity * wCreator)
                + (langAff * wLang)

            // Phase 4 Optimization: Time-Decay Factor (Symmetric)
            // Prioritize items airing/releasing soon or recently released.
            // Items without an assigned date are excluded from "For You".
            guard let targetDate = item.cachedNextAiringDate ?? item.releaseDate else {
                continue
            }

            let daysDifference = abs(now.timeIntervalSince(targetDate)) / 86400.0
            // Inverse time decay: 1 / (1 + λ * days)
            // λ = 0.005 ensures ~21% score retention at 2 years (730 days)
            let timeDecay = 1.0 / (1.0 + 0.005 * daysDifference)

            let finalScore = totalScore * timeDecay

            if finalScore > 0 {
                let bestReason: String = {
                    // Normalize reasons by weights so they match the user's priority
                    let weightedReasons = potentialReasons.map {
                        (label, aff, type) -> (String, Double) in
                        let weight: Double = {
                            switch type {
                            case 0: return wGenre
                            case 1: return wCreator
                            case 2: return wCast
                            case 3: return wLang
                            default: return 1.0
                            }
                        }()
                        return (label, aff * weight)
                    }

                    return weightedReasons.max(by: { $0.1 < $1.1 })?.0 ?? "Picked for you"
                }()

                recommendations.append((item.persistentModelID, finalScore, bestReason))
            }
        }

        return recommendations.sorted { $0.score > $1.score }.prefix(10).map { ($0.id, $0.reason) }
    }
}
