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
    func fetchTasteInsights() async -> TasteInsights {
        let profile = await calculateAffinityMaps()
        
        let sortedGenres = profile.genre.map { ($0.key, $0.value) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        
        // Use rich enrichment for Top 10 people
        var creatorResults: [(name: String, affinity: Double, imageURL: String?)] = []
        let topCreators = profile.creator.map { ($0.key, $0.value) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(10)
        
        for (name, affinity) in topCreators {
            let image = await resolvePersonImage(for: name)
            creatorResults.append((name, affinity, image))
        }

        var castResults: [(name: String, affinity: Double, imageURL: String?)] = []
        let topCast = profile.cast.map { ($0.key, $0.value) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(10)
            
        for (name, affinity) in topCast {
            let image = await resolvePersonImage(for: name)
            castResults.append((name, affinity, image))
        }
            
        let sortedLangs = profile.language.map { (LanguageUtils.languageName(for: $0.key), $0.value) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            
        return TasteInsights(
            genreAffinities: sortedGenres,
            creatorAffinities: creatorResults,
            castAffinities: castResults,
            languageAffinities: sortedLangs
        )
    }

    private func resolvePersonImage(for name: String) async -> String? {
        // 1. Check local Cache Entity
        let cacheDescriptor = FetchDescriptor<PersonImageEntity>(predicate: #Predicate { $0.name == name })
        if let cached = try? modelContext.fetch(cacheDescriptor).first {
            return cached.profileURL
        }

        // 2. Check Library CastMembers
        let castDescriptor = FetchDescriptor<CastMember>(predicate: #Predicate { $0.name == name })
        if let member = try? modelContext.fetch(castDescriptor).first(where: { $0.profileURL != nil }) {
            let url = member.profileURL
            // Save to cache for next time
            modelContext.insert(PersonImageEntity(name: name, profileURL: url))
            return url
        }

        // 3. On-Demand API Search
        if let path = try? await APIClient.shared.searchPerson(query: name) {
            let fullURL = "https://image.tmdb.org/t/p/w185\(path)"
            modelContext.insert(PersonImageEntity(name: name, profileURL: fullURL))
            try? modelContext.save()
            return fullURL
        }

        return nil
    }

    private func calculateAffinityMaps() async -> (genre: [String: Double], network: [String: Double], cast: [String: Double], creator: [String: Double], language: [String: Double]) {
        let descriptor = FetchDescriptor<MediaItem>()
        guard let allItems = try? modelContext.fetch(descriptor) else { return ([:], [:], [:], [:], [:]) }

        struct CategoryStats {
            var loved = 0
            var liked = 0
            var disliked = 0
            var total = 0
            func affinity(cutoff: Int = 5) -> Double {
                // CUTOFF: Customizable threshold
                guard total >= cutoff else { return 0 }
                return Double(3 * loved + 1 * liked - 2 * disliked) / Double(3 * total)
            }
        }

        var genreStats: [String: CategoryStats] = [:]
        var networkStats: [String: CategoryStats] = [:]
        var castStats: [String: CategoryStats] = [:]
        var creatorStats: [String: CategoryStats] = [:]
        var languageStats: [String: CategoryStats] = [:]
        
        let ratedItems = allItems.filter { $0.tasteValue != "None" }
        
        for item in ratedItems {
            let taste = item.tasteValue
            let update: (inout CategoryStats) -> Void = { stats in
                stats.total += 1
                if taste == "Love" { stats.loved += 1 }
                else if taste == "Like" { stats.liked += 1 }
                else if taste == "Dislike" { stats.disliked += 1 }
            }
            for g in item.cachedGenres { update(&genreStats[g, default: CategoryStats()]) }
            if let n = item.cachedNetwork { update(&networkStats[n, default: CategoryStats()]) }
            if let l = item.cachedLanguage { update(&languageStats[l, default: CategoryStats()]) }
            
            let cast = (item.movieDetails?.cast.map { $0.name } ?? item.tvShowDetails?.cast.map { $0.name } ?? [])
            for actor in cast { update(&castStats[actor, default: CategoryStats()]) }
            let creators = (item.movieDetails?.creators ?? item.tvShowDetails?.creators ?? [])
            for creator in creators { update(&creatorStats[creator, default: CategoryStats()]) }
        }
        
        return (
            genreStats.mapValues { $0.affinity(cutoff: 5) },
            networkStats.mapValues { $0.affinity(cutoff: 5) },
            castStats.mapValues { $0.affinity(cutoff: 5) }, // Increased to 5
            creatorStats.mapValues { $0.affinity(cutoff: 3) }, // Increased to 3
            languageStats.mapValues { $0.affinity(cutoff: 5) }
        )
    }

    func calculateRecommendations() async -> [(id: PersistentIdentifier, reason: String)] {
        // Fetch Weights from UserDefaults (matches AppStorage keys in UI)
        let wGenre = UserDefaults.standard.double(forKey: "taste_weight_genre") == 0 ? 30.0 : UserDefaults.standard.double(forKey: "taste_weight_genre")
        let wCreator = UserDefaults.standard.double(forKey: "taste_weight_creator") == 0 ? 30.0 : UserDefaults.standard.double(forKey: "taste_weight_creator")
        let wCast = UserDefaults.standard.double(forKey: "taste_weight_cast") == 0 ? 5.0 : UserDefaults.standard.double(forKey: "taste_weight_cast")
        let wNetwork = UserDefaults.standard.double(forKey: "taste_weight_network") == 0 ? 5.0 : UserDefaults.standard.double(forKey: "taste_weight_network")
        let wLang = UserDefaults.standard.double(forKey: "taste_weight_lang") == 0 ? 10.0 : UserDefaults.standard.double(forKey: "taste_weight_lang")

        let profile = await calculateAffinityMaps()
        let genreAffinity = profile.genre
        let networkAffinity = profile.network
        let castAffinity = profile.cast
        let creatorAffinity = profile.creator
        let langAffinity = profile.language
        
        let descriptor = FetchDescriptor<MediaItem>()
        guard let allItems = try? modelContext.fetch(descriptor) else { return [] }
        
        let wishlist = allItems.filter { $0.stateValue == "Wishlist" }
        var recommendations: [(id: PersistentIdentifier, score: Double, reason: String)] = []
        
        for item in wishlist {
            var potentialReasons: [(String, Double, Int)] = [] // Label, Affinity, Priority (0=Genre, 1=Creator, 2=Other)
            
            // Genre matching
            var genreTotalAffinity: Double = 0
            for g in item.cachedGenres {
                if let aff = genreAffinity[g], aff != 0 {
                    genreTotalAffinity += aff
                    potentialReasons.append(("Because you like \(g)", aff, 0))
                }
            }
            let genreAverageAffinity = item.cachedGenres.isEmpty ? 0 : (genreTotalAffinity / Double(item.cachedGenres.count))
            
            // Network matching
            var networkAff: Double = 0
            if let n = item.cachedNetwork, let aff = networkAffinity[n], aff != 0 {
                networkAff = aff
                potentialReasons.append(("From \(n)", aff, 2))
            }

            // Language matching
            var langAff: Double = 0
            if let l = item.cachedLanguage, let aff = langAffinity[l], aff != 0 {
                langAff = aff
                potentialReasons.append(("In \(l)", aff, 3))
            }
            
            // Cast matching (Reduced Weight with Decay)
            var castTotalAffinity: Double = 0
            let itemCast = (item.movieDetails?.cast.map { $0.name } ?? item.tvShowDetails?.cast.map { $0.name } ?? [])
            for (idx, actor) in itemCast.prefix(5).enumerated() {
                if let aff = castAffinity[actor], aff != 0 {
                    let decay = idx < 1 ? 1.0 : 0.5
                    castTotalAffinity += (aff * decay)
                    potentialReasons.append(("Starring \(actor)", aff, 2))
                }
            }
            
            // Creator matching
            var creatorTotalAffinity: Double = 0
            let itemCreators = (item.movieDetails?.creators ?? item.tvShowDetails?.creators ?? [])
            for creator in itemCreators {
                if let aff = creatorAffinity[creator], aff != 0 {
                    creatorTotalAffinity += aff
                    potentialReasons.append(("\(item.type == .movie ? "Directed by" : "Created by") \(creator)", aff, 1))
                }
            }
            
            let totalScore = (genreAverageAffinity * wGenre) + 
                             (networkAff * wNetwork) + 
                             (castTotalAffinity * wCast) + 
                             (creatorTotalAffinity * wCreator) +
                             (langAff * wLang)
            
            if totalScore > 0 {
                let bestReason: String = {
                    // Normalize reasons by weights so they match the user's priority
                    let weightedReasons = potentialReasons.map { (label, aff, type) -> (String, Double) in
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
                
                recommendations.append((item.persistentModelID, totalScore, bestReason))
            }
        }
        
        return recommendations.sorted { $0.score > $1.score }.prefix(8).map { ($0.id, $0.reason) }
    }
}
