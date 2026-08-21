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
        recommendations = result.recommendations
        
        // Prewarm thumbnail images as soon as data arrives — before views appear
        prewarmCarouselImages()
    }
    
    private func prewarmCarouselImages() {
        let cache = ImageCache.shared
        
        // Continue Watching & Featured Upcoming — hero thumbnails at .thumbMedium
        cache.prewarmImages(homeContinueWatchingItems, limit: 10, targetSize: .thumbMedium, priority: .normal)
        cache.prewarmImages(featuredUpcomingItems, limit: 10, targetSize: .thumbMedium, priority: .normal)
        
        // Pick of the Day & For You — each card loads 2 images (poster + backdrop)
        cache.prewarmImages(pickOfTheDay, limit: 6, targetSize: .thumbSmall, priority: .normal)
        cache.prewarmImages(recommendations, limit: 6, targetSize: .thumbSmall, priority: .normal)
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
        // Track which lists actually changed to avoid animating 7+ lists for a single-item update
        var changedLists: [String] = []

        let mutate = {
            let track = { (name: String, list: inout [MediaThumbnailMetadata]) in
                let before = list.count
                self.replaceInList(&list, id: id, updated: updated)
                if list.count != before { changedLists.append(name) }
            }

            track("displayed", &self.displayedItems)
            track("recentlyAdded", &self.recentlyAddedItems)
            track("continueWatching", &self.homeContinueWatchingItems)
            track("featuredUpcoming", &self.featuredUpcomingItems)
            track("recommendations", &self.recommendations)
            track("pickOfTheDay", &self.pickOfTheDay)

            for i in 0..<self.groupedItems.count {
                let before = self.groupedItems[i].1.count
                self.replaceInList(&self.groupedItems[i].1, id: id, updated: updated)
                if self.groupedItems[i].1.count != before { changedLists.append("grouped_\(i)") }
            }
        }

        if animated {
            withAnimation(AppTheme.Animation.easeInOut) { mutate() }
        } else {
            mutate()
        }
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
