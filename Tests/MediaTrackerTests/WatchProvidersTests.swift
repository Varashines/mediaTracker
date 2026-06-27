import XCTest
@testable import MediaTracker

final class WatchProvidersTests: XCTestCase {

    // MARK: - Helpers

    private func makeResponse(regions: [String: TMDBWatchRegion]) -> TMDBWatchProvidersResponse {
        TMDBWatchProvidersResponse(results: regions)
    }

    private func makeProvider(id: Int, name: String) -> TMDBWatchProvider {
        TMDBWatchProvider(provider_id: id, provider_name: name, logo_path: "/\(name.lowercased()).png")
    }

    // MARK: - Tests

    /// Verifies basic extraction of flatrate providers for the IN region
    func testExtractsProvidersForIndiaRegion() {
        let region = TMDBWatchRegion(
            flatrate: [
                makeProvider(id: 8, name: "Netflix"),
                makeProvider(id: 337, name: "Disney+"),
            ],
            free: nil,
            ads: nil
        )
        let response = makeResponse(regions: ["IN": region])
        let providers = extractWatchProviders(from: response, regionOverride: "IN")

        XCTAssertEqual(providers.count, 2)
        XCTAssertTrue(providers.contains(where: { $0.name == "Netflix" }))
        XCTAssertTrue(providers.contains(where: { $0.name == "Disney+" }))
    }

    /// Verifies that flatrate + free providers are merged
    func testMergesFlatrateAndFreeProviders() {
        let region = TMDBWatchRegion(
            flatrate: [makeProvider(id: 8, name: "Netflix")],
            free: [makeProvider(id: 283, name: "Crunchyroll")],
            ads: nil
        )
        let response = makeResponse(regions: ["IN": region])
        let providers = extractWatchProviders(from: response, regionOverride: "IN")

        XCTAssertEqual(providers.count, 2)
        XCTAssertTrue(providers.contains(where: { $0.name == "Netflix" }))
        XCTAssertTrue(providers.contains(where: { $0.name == "Crunchyroll" }))
    }

    /// Verifies that blocklisted provider IDs are filtered out
    func testFiltersBlocklistedProviders() {
        let region = TMDBWatchRegion(
            flatrate: [
                makeProvider(id: 8, name: "Netflix"),
                makeProvider(id: 502, name: "Tata Play"),        // blocklisted
                makeProvider(id: 614, name: "VI movies and tv"), // blocklisted
            ],
            free: nil,
            ads: nil
        )
        let response = makeResponse(regions: ["IN": region])
        let providers = extractWatchProviders(from: response, regionOverride: "IN")

        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers.first?.name, "Netflix")
        XCTAssertFalse(providers.contains(where: { $0.id == 502 }))
        XCTAssertFalse(providers.contains(where: { $0.id == 614 }))
    }

    /// Verifies that Amazon Channel add-ons are filtered out
    func testFiltersAmazonChannels() {
        let region = TMDBWatchRegion(
            flatrate: [
                makeProvider(id: 8, name: "Netflix"),
                makeProvider(id: 3000, name: "Paramount+ Amazon Channel"),
                makeProvider(id: 3001, name: "HBO Max Prime Video Channel")
            ],
            free: nil,
            ads: nil
        )
        let response = makeResponse(regions: ["IN": region])
        let providers = extractWatchProviders(from: response, regionOverride: "IN")

        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers.first?.name, "Netflix")
        XCTAssertFalse(providers.contains(where: { $0.id == 3000 }))
        XCTAssertFalse(providers.contains(where: { $0.id == 3001 }))
    }

    /// Verifies that Apple TV Channels are filtered out
    func testFiltersAppleTVChannels() {
        let region = TMDBWatchRegion(
            flatrate: [
                makeProvider(id: 8, name: "Netflix"),
                makeProvider(id: 4000, name: "MLS Season Pass Apple TV Channel"),
                makeProvider(id: 4001, name: "Paramount+ Apple TV Channel")
            ],
            free: nil,
            ads: nil
        )
        let response = makeResponse(regions: ["IN": region])
        let providers = extractWatchProviders(from: response, regionOverride: "IN")

        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers.first?.name, "Netflix")
        XCTAssertFalse(providers.contains(where: { $0.id == 4000 }))
        XCTAssertFalse(providers.contains(where: { $0.id == 4001 }))
    }

    /// Verifies that duplicate provider entries are deduplicated
    func testDeduplicatesProviders() {
        let region = TMDBWatchRegion(
            flatrate: [makeProvider(id: 8, name: "Netflix")],
            free: [makeProvider(id: 8, name: "Netflix")], // duplicate
            ads: nil
        )
        let response = makeResponse(regions: ["IN": region])
        let providers = extractWatchProviders(from: response, regionOverride: "IN")

        XCTAssertEqual(providers.count, 1)
    }

    /// Verifies that empty/nil response returns an empty array
    func testReturnsEmptyForNilResponse() {
        let providers = extractWatchProviders(from: nil, regionOverride: "IN")
        XCTAssertTrue(providers.isEmpty)
    }

    /// Verifies that missing region returns empty (no US fallback per design)
    func testReturnsEmptyWhenRegionNotPresent() {
        let region = TMDBWatchRegion(
            flatrate: [makeProvider(id: 8, name: "Netflix")],
            free: nil,
            ads: nil
        )
        let response = makeResponse(regions: ["US": region])
        // Force IN override — should return [] since IN data is absent
        let providers = extractWatchProviders(from: response, regionOverride: "IN")
        XCTAssertTrue(providers.isEmpty)
    }

    /// Verifies logo URL is correctly constructed from logo_path
    func testLogoURLIsConstructedCorrectly() {
        let region = TMDBWatchRegion(
            flatrate: [makeProvider(id: 8, name: "Netflix")],
            free: nil,
            ads: nil
        )
        let response = makeResponse(regions: ["IN": region])
        let providers = extractWatchProviders(from: response, regionOverride: "IN")

        XCTAssertNotNil(providers.first?.logoURL)
        XCTAssertTrue(providers.first?.logoURL?.contains("image.tmdb.org") == true)
    }
}
