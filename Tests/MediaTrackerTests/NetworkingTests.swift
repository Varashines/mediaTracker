import XCTest
@testable import MediaTracker

final class NetworkingTests: XCTestCase {
    var mockSession: URLSession!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)
        UserDefaults.standard.set("fake_tmdb_key", forKey: "tmdb_api_key")
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        UserDefaults.standard.removeObject(forKey: "tmdb_api_key")
        UserDefaults.standard.removeObject(forKey: "omdb_api_key")
    }

    func testSearchMovies() async throws {
        let json = """
        {
            "results": [
                {"id": 1, "title": "Test Movie", "overview": "An overview", "poster_path": "/poster.jpg", "backdrop_path": null, "release_date": "2026-01-01", "genre_ids": [28], "original_language": "en", "vote_average": 7.5, "popularity": 100}
            ]
        }
        """

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("search/movie") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json.data(using: .utf8))
        }

        let client = APIClient(testing: mockSession)
        let results = try await client.searchMovies(query: "test")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Test Movie")
        XCTAssertEqual(results.first?.id, "1")
    }

    func testSearchTVShows() async throws {
        let json = """
        {
            "results": [
                {"id": 2, "name": "Test Show", "overview": "A show", "poster_path": null, "backdrop_path": null, "first_air_date": "2026-01-01", "genre_ids": [18], "original_language": "en", "vote_average": 8.0, "popularity": 90}
            ]
        }
        """

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("search/tv") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json.data(using: .utf8))
        }

        let client = APIClient(testing: mockSession)
        let results = try await client.searchTVShows(query: "show")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Test Show")
    }

    func testFetchMovieDetails() async throws {
        let json = """
        {
            "id": 1,
            "runtime": 120,
            "genres": [{"name": "Action"}],
            "vote_average": 7.5,
            "release_date": "2026-01-01",
            "backdrop_path": null,
            "poster_path": null,
            "overview": "A great movie",
            "original_language": "en",
            "credits": {"cast": [], "crew": []},
            "release_dates": {"results": []},
            "production_companies": [],
            "external_ids": null
        }
        """

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("movie/1") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json.data(using: .utf8))
        }

        let client = APIClient(testing: mockSession)
        let details = try await client.fetchMovieDetails(tmdbID: 1)

        XCTAssertEqual(details.runtime, 120)
        XCTAssertEqual(details.genres, ["Action"])
        XCTAssertEqual(details.voteAverage, 7.5)
        XCTAssertEqual(details.overview, "A great movie")
    }

    func testFetchTVDetails() async throws {
        let json = """
        {
            "id": 1,
            "number_of_seasons": 2,
            "number_of_episodes": 20,
            "status": "Returning Series",
            "vote_average": 8.0,
            "genres": [{"name": "Drama"}],
            "backdrop_path": null,
            "poster_path": null,
            "overview": "A great show",
            "original_language": "en",
            "networks": [{"name": "Netflix", "logo_path": "/netflix.png"}],
            "created_by": [],
            "seasons": [{"season_number": 1, "name": "S1", "episode_count": 10, "air_date": "2026-01-01"}],
            "first_air_date": "2026-01-01",
            "next_episode_to_air": null,
            "external_ids": null,
            "credits": {"cast": [], "crew": []},
            "aggregate_credits": null
        }
        """

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("tv/1") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json.data(using: .utf8))
        }

        let client = APIClient(testing: mockSession)
        let details = try await client.fetchTVDetails(tmdbID: 1)

        XCTAssertEqual(details.status, "Returning Series")
        XCTAssertEqual(details.genres, ["Drama"])
        XCTAssertEqual(details.seasonsCount, 2)
        XCTAssertEqual(details.episodesCount, 20)
    }

    func testRateLimitRetry() async throws {
        var callCount = 0
        let json = """
        {"results": [{"id": 1, "title": "Retried", "overview": "", "poster_path": null, "backdrop_path": null, "release_date": null, "genre_ids": [], "original_language": "en", "vote_average": 0, "popularity": 0}]}
        """

        MockURLProtocol.requestHandler = { request in
            callCount += 1
            if callCount == 1 {
                let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
                return (response, nil)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json.data(using: .utf8))
        }

        let client = APIClient(testing: mockSession)
        let results = try await client.searchMovies(query: "retry")

        XCTAssertEqual(callCount, 2, "Should retry after rate limit")
        XCTAssertEqual(results.count, 1)
    }

    func testMissingAPIKeyThrows() async {
        UserDefaults.standard.removeObject(forKey: "tmdb_api_key")
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{}".data(using: .utf8))
        }

        let client = APIClient(testing: mockSession)
        do {
            _ = try await client.searchMovies(query: "test")
            XCTFail("Should throw missing API key")
        } catch {
            XCTAssertTrue(error is APIError)
        }
    }

    func testInvalidResponseStatusCode() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }

        let client = APIClient(testing: mockSession)
        do {
            _ = try await client.searchMovies(query: "test")
            XCTFail("Should throw request failed")
        } catch APIError.requestFailed(let code) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testSearchCacheReturnsCachedResults() async throws {
        let json = """
        {"results": [{"id": 1, "title": "Cached", "overview": "", "poster_path": null, "backdrop_path": null, "release_date": null, "genre_ids": [], "original_language": "en", "vote_average": 0, "popularity": 0}]}
        """

        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json.data(using: .utf8))
        }

        let client = APIClient(testing: mockSession)

        // First call hits network
        let first = try await client.searchMovies(query: "cache_test")
        XCTAssertEqual(callCount, 1)

        // Second call with same query should use cache (no network)
        let second = try await client.searchMovies(query: "cache_test")
        XCTAssertEqual(callCount, 1, "Should use cache, not network")
        XCTAssertEqual(first.count, second.count)
    }

    func testFetchSeasonDetails() async throws {
        let json = """
        {
            "episodes": [
                {"episode_number": 1, "name": "Pilot", "overview": "First ep", "air_date": "2026-01-01", "runtime": 45},
                {"episode_number": 2, "name": "Second", "overview": "Second ep", "air_date": "2026-01-08", "runtime": 45}
            ]
        }
        """

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("season/1") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json.data(using: .utf8))
        }

        let client = APIClient(testing: mockSession)
        let episodes = try await client.fetchSeasonDetails(tmdbID: 1, seasonNumber: 1)

        XCTAssertEqual(episodes.count, 2)
        XCTAssertEqual(episodes.first?.name, "Pilot")
        XCTAssertEqual(episodes.first?.episodeNumber, 1)
    }
}
