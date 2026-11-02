import XCTest
import SwiftData
import SwiftUI
@testable import MediaTracker

final class DetailViewModelTests: MTTestCase {
    @MainActor
    func testNeedsUpdateReturnsTrueWhenLastUpdatedIsNil() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, configurations: config)
        let context = container.mainContext
        let item = MediaItem(id: "1", title: "Movie", overview: "", type: .movie)
        context.insert(item)
        try context.save()

        let vm = DetailViewModel(item: item)
        XCTAssertTrue(vm.needsUpdate)
    }

    @MainActor
    func testNeedsUpdateReturnsFalseWhenRecentlyUpdated() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, configurations: config)
        let context = container.mainContext
        let item = MediaItem(id: "1", title: "Movie", overview: "", type: .movie)
        item.lastUpdated = Date()
        context.insert(item)
        try context.save()

        let vm = DetailViewModel(item: item)
        XCTAssertFalse(vm.needsUpdate)
    }

    @MainActor
    func testNeedsUpdateReturnsTrueWhenStale() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, configurations: config)
        let context = container.mainContext
        let item = MediaItem(id: "1", title: "Movie", overview: "", type: .movie)
        item.lastUpdated = Date().addingTimeInterval(-.days7)
        context.insert(item)
        try context.save()

        let vm = DetailViewModel(item: item)
        XCTAssertTrue(vm.needsUpdate)
    }

    @MainActor
    func testUpdateThemeColorWithPosterHex() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, configurations: config)
        let context = container.mainContext
        let item = MediaItem(id: "1", title: "Movie", overview: "", type: .movie)
        item.themeColorHex = "#FF0000"
        context.insert(item)
        try context.save()

        let vm = DetailViewModel(item: item)
        vm.updateThemeColor()
        XCTAssertNotEqual(vm.themeColor, Color.secondary.opacity(0.15))
    }

    @MainActor
    func testUpdateThemeColorFallback() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, configurations: config)
        let context = container.mainContext
        let item = MediaItem(id: "1", title: "Movie", overview: "", type: .movie)
        context.insert(item)
        try context.save()

        let vm = DetailViewModel(item: item)
        vm.updateThemeColor()
        // Fallback should not be clear
        XCTAssertNotEqual(vm.themeColor, .clear)
    }

    @MainActor
    func testToggleWatchedTogglesMovieToCompleted() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, configurations: config)
        let context = container.mainContext
        let item = MediaItem(id: "1", title: "Movie", overview: "", type: .movie)
        item.state = .wishlist
        context.insert(item)
        try context.save()

        let vm = DetailViewModel(item: item)
        vm.toggleWatched()
        XCTAssertEqual(item.state, .completed)
    }

    @MainActor
    func testToggleWatchedTogglesCompletedMovieToWishlist() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, configurations: config)
        let context = container.mainContext
        let item = MediaItem(id: "1", title: "Movie", overview: "", type: .movie)
        item.state = .completed
        context.insert(item)
        try context.save()

        let vm = DetailViewModel(item: item)
        vm.toggleWatched()
        XCTAssertEqual(item.state, .wishlist)
    }

    @MainActor
    func testCycleStatusCyclesThroughStates() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, configurations: config)
        let context = container.mainContext
        let item = MediaItem(id: "1", title: "Movie", overview: "", type: .movie)
        item.state = .wishlist
        context.insert(item)
        try context.save()

        let vm = DetailViewModel(item: item)
        vm.cycleStatus()
        XCTAssertEqual(item.state, .active)
    }

    @MainActor
    func testMarkAllAsWatchedSetsCompleted() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, configurations: config)
        let context = container.mainContext
        let item = MediaItem(id: "1", title: "Movie", overview: "", type: .movie)
        item.state = .wishlist
        context.insert(item)
        try context.save()

        let vm = DetailViewModel(item: item)
        vm.markAllAsWatched()
        XCTAssertEqual(item.state, .completed)
    }

    @MainActor
    func testNeedsUpdateForTVShowRequiresMaintenanceAfter30Days() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, configurations: config)
        let context = container.mainContext
        let item = MediaItem(id: "1", title: "Show", overview: "", type: .tvShow)
        item.lastUpdated = Date().addingTimeInterval(-.days30 - 1)
        context.insert(item)
        try context.save()

        let vm = DetailViewModel(item: item)
        XCTAssertTrue(vm.needsUpdate)
    }

    /// Recommendation ownership is resolved once into a set, replacing the
    /// per-card `fetchCount` that used to run inside the view body.
    @MainActor
    func testResolveRecommendationPresenceBuildsSetOfLibraryIDs() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, configurations: config)
        let context = container.mainContext

        let host = MediaItem(id: "movie_1", title: "Host", overview: "", type: .movie)
        context.insert(host)
        context.insert(MediaItem(id: "movie_101", title: "In Library", overview: "", type: .movie))
        context.insert(MediaItem(id: "tv_202", title: "In Library Show", overview: "", type: .tvShow))
        let deleted = MediaItem(id: "movie_303", title: "Deleted", overview: "", type: .movie)
        deleted.isSoftDeleted = true
        context.insert(deleted)
        try context.save()

        let vm = DetailViewModel(item: host)
        vm.tmdbRecommendations = [
            MediaSearchResult(id: "101", title: "In Library", overview: "", posterURL: nil, releaseDate: nil, genres: [], type: .movie, originalLanguage: nil),
            MediaSearchResult(id: "202", title: "In Library Show", overview: "", posterURL: nil, releaseDate: nil, genres: [], type: .tvShow, originalLanguage: nil),
            MediaSearchResult(id: "999", title: "Not In Library", overview: "", posterURL: nil, releaseDate: nil, genres: [], type: .movie, originalLanguage: nil),
            MediaSearchResult(id: "303", title: "Deleted", overview: "", posterURL: nil, releaseDate: nil, genres: [], type: .movie, originalLanguage: nil),
        ]

        vm.resolveRecommendationPresence()

        XCTAssertEqual(vm.inLibraryRecommendationIDs, ["movie_101", "tv_202"])
    }
}
