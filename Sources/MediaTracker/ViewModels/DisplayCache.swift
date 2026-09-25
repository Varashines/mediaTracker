import Foundation
import SwiftUI
import SwiftData

@Observable @MainActor
class DisplayCache {
    var displayedItems: [MediaThumbnailMetadata] = []
    var recentlyAddedItems: [MediaThumbnailMetadata] = []
    var homeContinueWatchingItems: [MediaThumbnailMetadata] = []
    var groupedItems: [(String, [MediaThumbnailMetadata])] = []
    var recommendations: [MediaThumbnailMetadata] = []
    /// True once a recommendations fetch has settled (even empty), so the
    /// For You row can tell loading skeletons apart from a real empty state.
    var recommendationsFetched = false
    var pickOfTheDay: [MediaThumbnailMetadata] = []
    var pickOfTheDayDate: Date? = nil
    var featuredUpcomingItems: [MediaThumbnailMetadata] = []
    var libraryTMDBIDs: Set<String> = []
    var calendarCache: [Date: CalendarResult] = [:]

    func purgeAll() {
        displayedItems = []
        recentlyAddedItems = []
        homeContinueWatchingItems = []
        groupedItems = []
        recommendations = []
        recommendationsFetched = false
        pickOfTheDay = []
        pickOfTheDayDate = nil
        featuredUpcomingItems = []
        libraryTMDBIDs = []
        calendarCache = [:]
    }

    /// Applies a full filter result atomically — all property mutations within this
    /// single call are coalesced into one SwiftUI observation notification.
    func applyFilterResult(_ result: PaginatedResult) {
        displayedItems = result.displayed
        featuredUpcomingItems = result.featuredUpcoming
        recentlyAddedItems = result.recentlyAdded
        homeContinueWatchingItems = result.homeContinueWatching
        groupedItems = result.grouped
        pickOfTheDay = result.pickOfTheDay
        if !result.recommendations.isEmpty {
            recommendations = result.recommendations
        }
        
        // Prewarm thumbnail images as soon as data arrives — before views appear
        prewarmCarouselImages()
    }
    
    private func prewarmCarouselImages() {
        let cache = ImageCache.shared

        cache.prewarmImages(displayedItems, limit: 18, targetSize: .thumbSmall, priority: .normal)
        cache.prewarmImages(recentlyAddedItems, limit: 8, targetSize: .thumbSmall, priority: .low)

        // Continue Watching — the always-visible first row: warm the full list
        // (not just the first screen) so scrubbing past item 8 is still warm.
        let cwBackdrops = homeContinueWatchingItems.compactMap(\.cardBackdropURL).compactMap(URL.init(string:))
        cache.prewarmImages(urls: cwBackdrops, targetSize: .backdropCompact, priority: .normal)

        // Title logos share the card decode size with ContinueWatchingBackdropCard
        // (.cardLogo) so the memory-cache key matches on first paint.
        let cwLogos = homeContinueWatchingItems.compactMap(\.logoURL).compactMap(URL.init(string:))
        cache.prewarmImages(urls: cwLogos, targetSize: .cardLogo, priority: .low)

        cache.prewarmImages(featuredUpcomingItems, limit: 8, targetSize: .thumbSmall, priority: .normal)

        // Pick of the Day & For You
        if !pickOfTheDay.isEmpty {
            cache.prewarmImages(pickOfTheDay, limit: 4, targetSize: .thumbSmall, priority: .low)
            let podBackdrops = pickOfTheDay.prefix(4).compactMap(\.cardBackdropURL).compactMap(URL.init(string:))
            cache.prewarmImages(urls: podBackdrops, targetSize: .backdropCompact, priority: .low)
        }
        if !recommendations.isEmpty {
            cache.prewarmImages(recommendations, limit: 6, targetSize: .thumbSmall, priority: .low)
            let recBackdrops = recommendations.prefix(6).compactMap(\.cardBackdropURL).compactMap(URL.init(string:))
            cache.prewarmImages(urls: recBackdrops, targetSize: .backdropCompact, priority: .low)
            let recLogos = recommendations.prefix(6).compactMap(\.logoURL).compactMap(URL.init(string:))
            cache.prewarmImages(urls: recLogos, targetSize: .cardLogo, priority: .low)
        }
    }

    /// Keeps a bounded calendar window around the currently displayed month.
    /// Adjacent-month preloading remains instant while repeated navigation cannot
    /// retain an unbounded number of historical or future months.
    func trimCalendarCache(around month: Date, keepMonthsEachDirection: Int = 6) {
        let calendar = Calendar.current
        let normalizedMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let lowerBound = calendar.date(byAdding: .month, value: -keepMonthsEachDirection, to: normalizedMonth) ?? normalizedMonth
        let upperBound = calendar.date(byAdding: .month, value: keepMonthsEachDirection, to: normalizedMonth) ?? normalizedMonth
        calendarCache = calendarCache.filter { $0.key >= lowerBound && $0.key <= upperBound }
    }

    /// Applies a single-item update to every list this cache owns that may reference
    /// the item, with the option to animate. Centralizes the list-walking logic that
    /// used to be open-coded in `ContentView.updateSingleItemInContentView` and
    /// `FilteredLibraryGridView.updateSingleItem`. If `updated` is nil the item is
    /// removed from all lists.
    func applyUpdate(_ updated: MediaThumbnailMetadata?, id: PersistentIdentifier, animated: Bool = true) {
        let mutate = {
            self.replaceInList(&self.displayedItems, id: id, updated: updated)
            self.replaceInList(&self.recentlyAddedItems, id: id, updated: updated)
            self.replaceInList(&self.homeContinueWatchingItems, id: id, updated: updated)
            self.replaceInList(&self.featuredUpcomingItems, id: id, updated: updated)
            self.replaceInList(&self.recommendations, id: id, updated: updated)
            self.replaceInList(&self.pickOfTheDay, id: id, updated: updated)

            for i in 0..<self.groupedItems.count {
                self.replaceInList(&self.groupedItems[i].1, id: id, updated: updated)
            }
        }

        // No withAnimation: single-item metadata swaps don't need a full-list
        // relayout spring — SwiftUI's diff already crossfades the changed cell.
        // Animating every list mutation re-ran the ForEach with implicit anims.
        mutate()
    }

    private func replaceInList(_ list: inout [MediaThumbnailMetadata], id: PersistentIdentifier, updated: MediaThumbnailMetadata?) {
        if let index = list.firstIndex(where: { $0.id == id }) {
            if let updated {
                list[index] = updated
            } else {
                list.remove(at: index)
            }
        }
    }
}
