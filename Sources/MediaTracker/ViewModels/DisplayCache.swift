import Foundation

@Observable @MainActor
class DisplayCache {
    var displayedItems: [MediaThumbnailMetadata] = []
    var recentlyAddedItems: [MediaThumbnailMetadata] = []
    var homeContinueWatchingItems: [MediaThumbnailMetadata] = []
    var spotlightHero: MediaThumbnailMetadata? = nil
    var groupedItems: [(String, [MediaThumbnailMetadata])] = []
    var recommendations: [MediaThumbnailMetadata] = []
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
        featuredUpcomingItems = []
        libraryTMDBIDs = []
        isLibraryMetadataDirty = true
        calendarCache = [:]
    }

    func trimCalendarCache(keepMonths: Int = 6) {
        let cutoff = Calendar.current.date(byAdding: .month, value: -keepMonths, to: Date()) ?? Date()
        calendarCache = calendarCache.filter { $0.key >= cutoff }
    }
}
