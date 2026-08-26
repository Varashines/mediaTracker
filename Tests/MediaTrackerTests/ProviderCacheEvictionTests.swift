import XCTest
@testable import MediaTracker

/// Regression tests for the provider-cache LRU eviction cap. This guards the
/// `cacheProviders` helper — a recursion bug here previously crashed the whole
/// test process (stack overflow), so any regression must fail loudly here.
final class ProviderCacheEvictionTests: XCTestCase {

    private nonisolated(unsafe) static var requestCount = 0
    private static let lock = NSLock()

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

    /// Provider payload covering many regions so the runner locale always finds
    /// a non-empty flatrate list (required for the memory-hit branch to engage).
    private static func providersJSON() -> Data {
        let regionBody = """
        {"link": "https://www.themoviedb.org/watch", "flatrate": [
            {"logo_path": "/netflix.png", "provider_id": 8, "provider_name": "Netflix", "display_priority": 1}
        ]}
        """
        let regions = ["US", "GB", "CA", "AU", "DE", "FR", "IN", "JP", "BR", "ES", "IT", "NL", "KR", "MX", "SE"]
            .map { "\($0): \(regionBody)" }
            .joined(separator: ",")
        return "{\"results\": {\(regions)}}".data(using: .utf8)!
    }

    func testProviderCacheEvictsOldestBeyondCap() async throws {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)

        MockURLProtocol.requestHandler = { request in
            Self.incrementRequestCount()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Self.providersJSON())
        }
        defer { MockURLProtocol.requestHandler = nil }

        let client = APIClient(testing: mockSession)

        // Populate the cache past its 300-entry cap. Every call is a network
        // fetch (nothing else populates the in-memory provider cache).
        for id in 1...305 {
            _ = await client.fetchWatchProviders(tmdbID: id, type: .movie)
        }

        let baseline = Self.currentRequestCount()

        // Most-recent entry (305) must still be served from memory.
        _ = await client.fetchWatchProviders(tmdbID: 305, type: .movie)
        XCTAssertEqual(Self.currentRequestCount(), baseline, "Recently cached provider should be served from memory without a new request")

        // Oldest entry (1) was evicted when the cap was exceeded → refetch.
        _ = await client.fetchWatchProviders(tmdbID: 1, type: .movie)
        XCTAssertEqual(Self.currentRequestCount(), baseline + 1, "Evicted oldest entry should trigger exactly one fresh request")

        // The re-fetched entry is now the most recent → served from memory again.
        _ = await client.fetchWatchProviders(tmdbID: 1, type: .movie)
        XCTAssertEqual(Self.currentRequestCount(), baseline + 1, "Re-inserted entry should be cached again")
    }

    func testProviderCacheServesRepeatLookupsFromMemory() async throws {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)

        MockURLProtocol.requestHandler = { request in
            Self.incrementRequestCount()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Self.providersJSON())
        }
        defer { MockURLProtocol.requestHandler = nil }

        let client = APIClient(testing: mockSession)

        _ = await client.fetchWatchProviders(tmdbID: 42, type: .tvShow)
        let afterFirst = Self.currentRequestCount()

        for _ in 0..<3 {
            _ = await client.fetchWatchProviders(tmdbID: 42, type: .tvShow)
        }
        XCTAssertEqual(Self.currentRequestCount(), afterFirst, "Repeated lookups within the cap should never hit the network again")
    }
}
