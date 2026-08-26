import XCTest
@testable import MediaTracker

/// Regression tests for the provider-cache LRU eviction cap. This guards the
/// `cacheProviders` helper — a recursion bug here previously crashed the whole
/// test process (stack overflow), so any regression must fail loudly here.
final class ProviderCacheEvictionTests: XCTestCase {

    private nonisolated(unsafe) static var requestCount = 0
    private static let lock = NSLock()

    override func setUp() {
        super.setUp()
        // tmdbURL throws before any network request when the key is missing;
        // NetworkingTests' tearDown removes its stub, so set our own.
        UserDefaults.standard.set("fake_tmdb_key", forKey: "tmdb_api_key")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "tmdb_api_key")
        super.tearDown()
    }

    private static func incrementRequestCount() {
        lock.lock()
        defer { lock.unlock() }
        requestCount += 1
    }

    private static func currentRequestCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    /// Provider payload covering the runner's actual region (plus common
    /// fallbacks) so `extractWatchProviders` always finds a non-empty flatrate
    /// list — required for the memory-hit branch to engage.
    private static func providersJSON() -> Data {
        let regionBody = """
        {"link": "https://www.themoviedb.org/watch", "flatrate": [
            {"logo_path": "/netflix.png", "provider_id": 8, "provider_name": "Netflix", "display_priority": 1}
        ]}
        """
        let runnerRegion = Locale.current.region?.identifier ?? "US"
        var regions = ["US", "GB", "CA", "AU", "DE", "FR", "IN", "JP", "BR", "ES", "IT", "NL", "KR", "MX", "SE"]
        regions.insert(runnerRegion, at: 0)
        let regionEntries = regions
            .map { "\"\($0)\": \(regionBody)" }
            .joined(separator: ",")
        return "{\"results\": {\(regionEntries)}}".data(using: .utf8)!
    }

    func testProviderCacheEvictsOldestBeyondCap() async throws {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)

        MockURLProtocol.requestHandler = { request in
            Self.incrementRequestCount()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "no-store"])!
            return (response, Self.providersJSON())
        }
        defer { MockURLProtocol.requestHandler = nil }

        let client = APIClient(testing: mockSession)

        // Diagnostic probe: the very first fetch must yield non-empty providers
        // (region match + decode). If this fails, the memory-hit branch below can
        // never engage and every lookup legitimately refetches.
        let probeID = 300_000_001
        let probe = await client.fetchWatchProviders(tmdbID: probeID, type: .movie)
        XCTAssertFalse(
            probe.isEmpty,
            "Mock providers decoded to empty for region \(Locale.current.region?.identifier ?? "nil") — memory cache will never engage"
        )

        // A second identical lookup must now come from memory (1 request total).
        _ = await client.fetchWatchProviders(tmdbID: probeID, type: .movie)
        XCTAssertEqual(Self.currentRequestCount(), 2, "Immediate repeat of a non-empty cached provider must not refetch")

        // Populate the cache past its 300-entry cap. Every call is a network
        // fetch (nothing else populates the in-memory provider cache).
        for id in 100_001...100_305 {
            _ = await client.fetchWatchProviders(tmdbID: id, type: .movie)
        }

        let baseline = Self.currentRequestCount()

        // Most-recent entry (305) must still be served from memory.
        _ = await client.fetchWatchProviders(tmdbID: 100_305, type: .movie)
        XCTAssertEqual(Self.currentRequestCount(), baseline, "Recently cached provider should be served from memory without a new request")

        // Oldest entry (100_001) was evicted when the cap was exceeded → refetch.
        _ = await client.fetchWatchProviders(tmdbID: 100_001, type: .movie)
        XCTAssertEqual(Self.currentRequestCount(), baseline + 1, "Evicted oldest entry should trigger exactly one fresh request")

        // The re-fetched entry is now the most recent → served from memory again.
        _ = await client.fetchWatchProviders(tmdbID: 100_001, type: .movie)
        XCTAssertEqual(Self.currentRequestCount(), baseline + 1, "Re-inserted entry should be cached again")
    }

    func testProviderCacheServesRepeatLookupsFromMemory() async throws {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)

        MockURLProtocol.requestHandler = { request in
            Self.incrementRequestCount()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "no-store"])!
            return (response, Self.providersJSON())
        }
        defer { MockURLProtocol.requestHandler = nil }

        let client = APIClient(testing: mockSession)

        _ = await client.fetchWatchProviders(tmdbID: 200_042, type: .tvShow)
        let afterFirst = Self.currentRequestCount()

        for _ in 0..<3 {
            _ = await client.fetchWatchProviders(tmdbID: 200_042, type: .tvShow)
        }
        XCTAssertEqual(Self.currentRequestCount(), afterFirst, "Repeated lookups within the cap should never hit the network again")
    }
}
