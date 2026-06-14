import Foundation
import SwiftUI
import SwiftData

@Observable @MainActor
class DisplayCache {
    var displayedItems: [MediaThumbnailMetadata] = []
    var recentlyAddedItems: [MediaThumbnailMetadata] = []
    var homeContinueWatchingItems: [MediaThumbnailMetadata] = []
    var spotlightHero: MediaThumbnailMetadata? = nil
    var groupedItems: [(String, [MediaThumbnailMetadata])] = []
    var recommendations: [MediaThumbnailMetadata] = []
    var pickOfTheDay: [MediaThumbnailMetadata] = []
    var pickOfTheDayDate: Date? = nil
    var featuredUpcomingItems: [MediaThumbnailMetadata] = []
    var libraryTMDBIDs: Set<String> = []
    var isLibraryMetadataDirty: Bool = true
    var calendarCache: [Date: CalendarResult] = [:]

    func purgeAll() {
        displayedItems = []
        recentlyAddedItems = []
        homeContinueWatchingItems = []
        spotlightHero = nil
        groupedItems = []
        recommendations = []
        pickOfTheDay = []
        pickOfTheDayDate = nil
        featuredUpcomingItems = []
        libraryTMDBIDs = []
        isLibraryMetadataDirty = true
        calendarCache = [:]
    }

    func trimCalendarCache(keepMonths: Int = 6) {
        let cutoff = Calendar.current.date(byAdding: .month, value: -keepMonths, to: Date()) ?? Date()
        calendarCache = calendarCache.filter { $0.key >= cutoff }
    }

    /// Applies a single-item update to every list this cache owns that may reference
    /// the item, with the option to animate. Centralizes the list-walking logic that
    /// used to be open-coded in `ContentView.updateSingleItemInContentView` and
    /// `FilteredLibraryGridView.updateSingleItem`. If `updated` is nil the item is
    /// removed from all lists.
    func applyUpdate(_ updated: MediaThumbnailMetadata?, id: PersistentIdentifier, animated: Bool = true) {
        // Track which lists actually changed to avoid animating 7+ lists for a single-item update
        var changedLists: [String] = []

        let track = { (name: String, list: inout [MediaThumbnailMetadata]) in
            let before = list.count
            self.replaceInList(&list, id: id, updated: updated)
            if list.count != before { changedLists.append(name) }
        }

        track("displayed", &displayedItems)
        track("recentlyAdded", &recentlyAddedItems)
        track("continueWatching", &homeContinueWatchingItems)
        track("featuredUpcoming", &featuredUpcomingItems)
        track("recommendations", &recommendations)
        track("pickOfTheDay", &pickOfTheDay)

        if let updated, self.spotlightHero?.id == id {
            self.spotlightHero = updated
            changedLists.append("spotlight")
        } else if self.spotlightHero?.id == id && updated == nil {
            self.spotlightHero = nil
            changedLists.append("spotlight")
        }

        for i in 0..<self.groupedItems.count {
            let before = self.groupedItems[i].1.count
            self.replaceInList(&self.groupedItems[i].1, id: id, updated: updated)
            if self.groupedItems[i].1.count != before { changedLists.append("grouped_\(i)") }
        }

        // Only animate if lists actually changed — avoids 7+ simultaneous animations
        guard !changedLists.isEmpty else { return }
        if animated {
            withAnimation(AppTheme.Animation.easeInOut) { }
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
