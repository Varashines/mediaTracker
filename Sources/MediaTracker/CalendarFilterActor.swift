import Foundation
import SwiftData

struct CalendarReleaseItem: Sendable, Identifiable {
    var id: PersistentIdentifier { metadata.id }
    let metadata: MediaThumbnailMetadata
    let releaseContext: String
    let date: Date
    let weight: Int
}

struct CalendarDayInfo: Sendable, Identifiable {
    var id: Date { date }
    let date: Date
    let items: [CalendarReleaseItem]
    let intensity: Double // 0.0 to 1.0
}

struct CalendarResult: Sendable {
    let days: [Date: CalendarDayInfo]
    let allItems: [CalendarReleaseItem]
    let startDate: Date
    let endDate: Date
}

@ModelActor
actor CalendarFilterActor {
    func fetchCalendarData(for month: Date) throws -> CalendarResult {
        try Task.checkCancellation()
        let calendar = Calendar.current
        let bounds = try calculateMonthBounds(for: month, calendar: calendar)
        
        try Task.checkCancellation()
        let movies = try fetchMoviesInRange(bounds: bounds)
        try Task.checkCancellation()
        let episodes = try fetchEpisodesInRange(bounds: bounds)
        
        var dailyItems: [Date: [CalendarReleaseItem]] = [:]
        var allProcessedItems: [CalendarReleaseItem] = []
        
        processMovies(movies, calendar: calendar, dailyItems: &dailyItems, allItems: &allProcessedItems)
        try processEpisodes(episodes, calendar: calendar, dailyItems: &dailyItems, allItems: &allProcessedItems)
        
        let dayInfos = finalizeDayInfos(dailyItems: dailyItems, bounds: bounds, calendar: calendar)
        
        return CalendarResult(
            days: dayInfos,
            allItems: allProcessedItems.sorted { $0.date < $1.date },
            startDate: bounds.start,
            endDate: bounds.end
        )
    }

    private struct MonthBounds {
        let start: Date
        let end: Date
    }

    private func calculateMonthBounds(for month: Date, calendar: Calendar) throws -> MonthBounds {
        let components = calendar.dateComponents([.year, .month], from: month)
        guard let startDate = calendar.date(from: components),
              let endDate = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) else {
            throw AppError.generic("Invalid month bounds")
        }
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))?.addingTimeInterval(-1) ?? endDate
        return MonthBounds(start: start, end: end)
    }

    private func fetchMoviesInRange(bounds: MonthBounds) throws -> [MediaItem] {
        let fallbackPast = Date.distantPast
        let fallbackFuture = Date.distantFuture
        let startOfDay = bounds.start
        let endOfDay = bounds.end

        let moviePredicate = #Predicate<MediaItem> { item in
            item.typeValue == "Movie" && item.cachedNextAiringDate != nil &&
            (item.cachedNextAiringDate ?? fallbackPast) >= startOfDay && (item.cachedNextAiringDate ?? fallbackFuture) <= endOfDay
        }
        var movieDesc = FetchDescriptor<MediaItem>(predicate: moviePredicate)
        movieDesc.propertiesToFetch = [
            \.id, \.title, \.posterURL, \.releaseDate, \.typeValue, \.themeColorHex,
            \.cachedNextAiringDate, \.cachedRuntime, \.storedProgress, \.stateValue
        ]
        var movies = try modelContext.fetch(movieDesc)

        let unindexedPredicate = #Predicate<MediaItem> { item in
            item.typeValue == "Movie" && item.cachedNextAiringDate == nil
        }
        var unindexedDesc = FetchDescriptor<MediaItem>(predicate: unindexedPredicate)
        unindexedDesc.propertiesToFetch = [
            \.id, \.title, \.posterURL, \.releaseDate, \.typeValue, \.themeColorHex,
            \.cachedNextAiringDate, \.cachedRuntime, \.storedProgress, \.stateValue
        ]
        let unindexed = (try? modelContext.fetch(unindexedDesc)) ?? []
        let matched = unindexed.filter { movie in
            guard let date = movie.releaseDate else { return false }
            return date >= startOfDay && date <= endOfDay
        }
        movies.append(contentsOf: matched)
        return movies
    }

    private func fetchEpisodesInRange(bounds: MonthBounds) throws -> [TVEpisode] {
        let fallbackPast = Date.distantPast
        let fallbackFuture = Date.distantFuture
        let startOfDay = bounds.start
        let endOfDay = bounds.end

        let episodePredicate = #Predicate<TVEpisode> { ep in
            ep.airDateValue != nil && (ep.airDateValue ?? fallbackPast) >= startOfDay && (ep.airDateValue ?? fallbackFuture) <= endOfDay
        }
        var descriptor = FetchDescriptor<TVEpisode>(predicate: episodePredicate)
        descriptor.fetchLimit = 300
        var episodes = try modelContext.fetch(descriptor)
        
        let unindexedPredicate = #Predicate<TVEpisode> { ep in ep.airDateValue == nil }
        let unindexedDescriptor = FetchDescriptor<TVEpisode>(predicate: unindexedPredicate)
        let unindexed = (try? modelContext.fetch(unindexedDescriptor)) ?? []
        let matched = unindexed.filter { ep in
            guard let date = ep.airDateAsDate else { return false }
            return date >= startOfDay && date <= endOfDay
        }
        if !matched.isEmpty {
            episodes.append(contentsOf: matched)
            // Queue date healing in a detached non-actor task to avoid blocking calendar fetches
            let container = modelContext.container
            Task.detached(priority: .background) {
                let ctx = ModelContext(container)
                Self.healMissingDatesSync(context: ctx)
            }
        }
        // Defensive: exclude any episodes deleted/detached during concurrent background merges
        return episodes.liveModels
    }

    private static func healMissingDatesSync(context: ModelContext) {
        let descriptor = FetchDescriptor<TVEpisode>(predicate: #Predicate { $0.airDateValue == nil })
        guard let episodes = try? context.fetch(descriptor), !episodes.isEmpty else { return }
        let batchSize = 50
        for i in stride(from: 0, to: episodes.count, by: batchSize) {
            let end = min(i + batchSize, episodes.count)
            for ep in episodes[i..<end] {
                ep.updateAirDateValue()
            }
            try? context.save()
        }
    }


    private func processMovies(_ movies: [MediaItem], calendar: Calendar, dailyItems: inout [Date: [CalendarReleaseItem]], allItems: inout [CalendarReleaseItem]) {
        for movie in movies {
            let date = movie.cachedNextAiringDate ?? movie.releaseDate ?? .distantPast
            if date != .distantPast {
                let day = calendar.startOfDay(for: date)
                let item = CalendarReleaseItem(metadata: Self.toMetadata(movie), releaseContext: "Movie Premiere", date: date, weight: 1)
                dailyItems[day, default: []].append(item)
                allItems.append(item)
            }
        }
    }

    private func processEpisodes(_ episodes: [TVEpisode], calendar: Calendar, dailyItems: inout [Date: [CalendarReleaseItem]], allItems: inout [CalendarReleaseItem]) throws {
        let grouped = Dictionary(grouping: episodes) { ep -> String in
            let day = calendar.startOfDay(for: ep.airDateAsDate ?? .distantPast)
            let showID = ep.season?.tvShowDetails?.item?.id ?? (ep.showID != nil ? String(ep.showID!) : UUID().uuidString)
            return "\(day.timeIntervalSince1970)_\(showID)"
        }
        
        for (_, eps) in grouped {
            guard let firstEp = eps.first, let airDate = firstEp.airDateAsDate else { continue }
            let day = calendar.startOfDay(for: airDate)
            
            var item = firstEp.season?.tvShowDetails?.item
            if item == nil, let showID = firstEp.showID {
                let idStr = "tv_\(showID)"
                item = try? modelContext.fetch(FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == idStr })).first
            }
            
            guard let foundItem = item else { continue }
            
            let season = firstEp.seasonNumber
            let sorted = eps.sorted { $0.episodeNumber < $1.episodeNumber }
            let context = sorted.count > 3 ? "Season \(season)" : "S\(season) " + sorted.map { "E\($0.episodeNumber)" }.joined(separator: ", ")
            
            let releaseItem = CalendarReleaseItem(metadata: Self.toMetadata(foundItem), releaseContext: context, date: airDate, weight: eps.count)
            dailyItems[day, default: []].append(releaseItem)
            allItems.append(releaseItem)
        }
    }

    private func finalizeDayInfos(dailyItems: [Date: [CalendarReleaseItem]], bounds: MonthBounds, calendar: Calendar) -> [Date: CalendarDayInfo] {
        var dayInfos: [Date: CalendarDayInfo] = [:]
        
        // Calculate total weight per day
        var dailyWeights: [Date: Int] = [:]
        for (date, items) in dailyItems {
            dailyWeights[date] = items.reduce(0) { $0 + $1.weight }
        }
        
        let maxWeight = Double(dailyWeights.values.max() ?? 1)
        let logMax = log1p(maxWeight)
        
        var current = bounds.start
        while current <= bounds.end {
            let items = dailyItems[current] ?? []
            let weight = Double(dailyWeights[current] ?? 0)
            let intensity = maxWeight > 0 ? log1p(weight) / logMax : 0
            dayInfos[current] = CalendarDayInfo(date: current, items: items, intensity: intensity)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dayInfos
    }

    private static func toMetadata(_ item: MediaItem) -> MediaThumbnailMetadata {
        MediaThumbnailMetadata(item: item)
    }
}
