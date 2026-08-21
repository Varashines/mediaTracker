import XCTest
import SwiftData
@testable import MediaTracker

@MainActor
final class SearchViewModelTests: XCTestCase {
    private var viewModel: SearchViewModel!

    override func setUp() {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        viewModel = SearchViewModel(modelContainer: container)
    }

    override func tearDown() {
        // Cancels the debounce task so performSearch never fires between tests.
        viewModel.cancelAllSearchOperations()
        viewModel = nil
    }

    func testIsSearchingSetImmediatelyDuringDebounceWindow() {
        XCTAssertFalse(viewModel.isSearching)
        viewModel.handleSearchTextChange("batman", selectedType: .movie)
        // Must be true synchronously — before the 150ms debounce fires —
        // so the skeleton shows instead of a no-results flash.
        XCTAssertTrue(viewModel.isSearching)
    }

    func testIsSearchingResetOnEmptyText() {
        viewModel.handleSearchTextChange("batman", selectedType: .movie)
        XCTAssertTrue(viewModel.isSearching)
        viewModel.handleSearchTextChange("", selectedType: .movie)
        XCTAssertFalse(viewModel.isSearching)
        XCTAssertTrue(viewModel.movieResults.isEmpty)
        XCTAssertTrue(viewModel.tvResults.isEmpty)
        XCTAssertTrue(viewModel.filteredLocalResults.isEmpty)
    }
}
