import XCTest
import SwiftData
import SwiftUI
@testable import MediaTracker

final class DetailViewModelTests: XCTestCase {
    @MainActor
    func testNeedsUpdateReturnsTrueWhenLastUpdatedIsNil() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
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
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
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
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
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
}
