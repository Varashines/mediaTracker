import XCTest
import SwiftData
@testable import MediaTracker

/// End-to-end sync scenarios: a real `CloudSyncService` against a stub PostgREST, so the whole
/// path — fetch, reconcile, apply, push — runs offline.
///
/// These pin the behaviours that have actually broken in this app, rather than the happy path:
/// conflicts decided on the user-edit time, the incremental watermark, the taste spelling the
/// other app writes, one watch logged twice, and corrections that have to travel to the ledger
/// as well as the projection.
final class CloudSyncScenarioTests: MTTestCase {

    // MARK: - Stub transport

    /// Minimal PostgREST. GETs answer from `tables` (honouring `updated_at=gt.`), POSTs upsert
    /// into them, and every request is recorded so a scenario can assert what was sent.
    final class StubPostgREST {
        struct Recorded {
            let method: String
            let table: String
            let query: String
            let body: [[String: Any]]
        }

        var tables: [String: [[String: Any]]] = [:]
        private(set) var recorded: [Recorded] = []

        /// Primary key column(s) per table, used to upsert.
        private let keys: [String: [String]] = [
            "user_media": ["media_id"],
            "user_episodes": ["episode_id"],
            "user_collections": ["collection_id"],
            "user_collection_items": ["collection_id", "media_id"],
            "user_watch_cycles": ["cycle_id"],
            "user_watch_events": ["event_id"]
        ]

        func posts(to table: String) -> [Recorded] { recorded.filter { $0.method == "POST" && $0.table == table } }
        func gets(of table: String) -> [Recorded] { recorded.filter { $0.method == "GET" && $0.table == table } }

        func respond(to request: URLRequest) throws -> (HTTPURLResponse, Data?) {
            let url = request.url!
            let table = url.pathComponents.last ?? ""
            let query = url.query?.removingPercentEncoding ?? ""
            let method = request.httpMethod ?? "GET"

            var body: [[String: Any]] = []
            if let data = request.httpBody ?? request.httpBodyStream.flatMap(Self.readAll) {
                body = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
            }
            recorded.append(Recorded(method: method, table: table, query: query, body: body))

            func http(_ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
                HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            }

            if method == "POST" {
                upsert(table: table, rows: body)
                // `Prefer: return=minimal` — the client only checks the status code.
                return (http(201, ["Content-Location": "/\(table)"]), nil)
            }

            var rows = tables[table] ?? []

            // `count=exact` + `limit=0`: PostgREST reports the total in Content-Range.
            if request.value(forHTTPHeaderField: "Prefer")?.contains("count=exact") == true {
                return (http(200, ["Content-Range": "*/\(rows.count)"]), Data("[]".utf8))
            }

            if let gt = Self.value(of: "updated_at", in: query, prefix: "gt.") {
                rows = rows.filter { ($0["updated_at"] as? String).map { $0 > gt } ?? false }
            }
            let data = try JSONSerialization.data(withJSONObject: rows)
            let range = rows.isEmpty ? "*/0" : "0-\(rows.count - 1)/*"
            return (http(200, ["Content-Range": range]), data)
        }

        private func upsert(table: String, rows: [[String: Any]]) {
            guard let keys = keys[table] else { return }
            var existing = tables[table] ?? []
            for row in rows {
                let matches: ([String: Any]) -> Bool = { candidate in
                    keys.allSatisfy { candidate[$0] as? String == row[$0] as? String }
                }
                if let index = existing.firstIndex(where: matches) {
                    existing[index] = row
                } else {
                    existing.append(row)
                }
            }
            tables[table] = existing
        }

        private static func value(of key: String, in query: String, prefix: String) -> String? {
            for part in query.split(separator: "&") {
                let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
                guard pair.count == 2, pair[0] == key, pair[1].hasPrefix(prefix) else { continue }
                // `gt.<stamp>` — the stamp itself may contain `=`, so take the remainder whole.
                return String(pair[1].dropFirst(prefix.count))
            }
            return nil
        }

        private static func readAll(_ stream: InputStream) -> Data? {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let size = 4096
            var buffer = [UInt8](repeating: 0, count: size)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: size)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return data
        }
    }

    // MARK: - Fixture

    private nonisolated(unsafe) var container: ModelContainer!
    private nonisolated(unsafe) var stub: StubPostgREST!

    /// Fractional seconds, to match what the client pushes — the stub filters `updated_at=gt.`
    /// by string comparison, so the formats have to agree.
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private var schema: Schema {
        Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self,
            SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self,
            WatchCycle.self, WatchEvent.self
        ])
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        UserDefaults.standard.set("https://stub.supabase.test", forKey: UserDefaultsKeys.cloudSyncURL.rawValue)
        UserDefaults.standard.set("stub-anon-key", forKey: UserDefaultsKeys.cloudSyncAnonKey.rawValue)
        UserDefaults.standard.set("mt_sync_scenarios", forKey: UserDefaultsKeys.cloudSyncKey.rawValue)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudSyncWatermark.rawValue)

        stub = StubPostgREST()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        CloudSyncService.session = URLSession(configuration: configuration)
        MockURLProtocol.requestHandler = { [stub] request in try stub!.respond(to: request) }

        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    override func tearDownWithError() throws {
        MockURLProtocol.requestHandler = nil
        CloudSyncService.session = .shared
        // Remove everything setUp wrote. Leaving the endpoint and keys behind makes
        // later suites believe cloud sync is configured, and leaving the timestamps
        // behind changes the conflict decisions of the next sync that runs.
        for key in [
            UserDefaultsKeys.cloudSyncURL.rawValue,
            UserDefaultsKeys.cloudSyncAnonKey.rawValue,
            UserDefaultsKeys.cloudSyncKey.rawValue,
            UserDefaultsKeys.cloudSyncWatermark.rawValue,
            UserDefaultsKeys.cloudSyncLastTimestamp.rawValue
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func stamp(_ offset: TimeInterval) -> String {
        iso.string(from: Date().addingTimeInterval(offset))
    }

    private func setWatermark(_ offset: TimeInterval) {
        UserDefaults.standard.set(stamp(offset), forKey: UserDefaultsKeys.cloudSyncWatermark.rawValue)
    }

    /// A media row as PostgREST returns it.
    private func cloudMedia(
        _ id: String,
        title: String = "T",
        type: String = "Movie",
        state: String = "Active",
        taste: String = "None",
        lastInteraction: String,
        updatedAt: String,
        softDeleted: Bool = false,
        dateAdded: String? = nil
    ) -> [String: Any] {
        var row: [String: Any] = [
            "user_id": "mt_sync_scenarios",
            "media_id": id,
            "type": type,
            "state": state,
            "taste": taste,
            "custom_poster_url": NSNull(),
            "is_soft_deleted": softDeleted,
            "last_interaction_date": lastInteraction,
            "last_state_change_date": lastInteraction,
            "updated_at": updatedAt
        ]
        row["date_added"] = dateAdded ?? NSNull()
        return row
    }

    @discardableResult
    @MainActor
    private func localMedia(id: String, state: MediaState = .active, tasteValue: String = "None",
                            lastInteraction: Date, dateAdded: Date? = nil) -> MediaItem {
        let item = MediaItem(id: id, title: "T", overview: "", type: .movie)
        item.stateValue = state.rawValue
        item.tasteValue = tasteValue
        item.lastInteractionDate = lastInteraction
        item.dateAdded = dateAdded
        container.mainContext.insert(item)
        return item
    }

    /// An episode only links to its show by `showID`; there is no relationship to insert.
    @MainActor
    private func localEpisode(showID: Int, season: Int, episode: Int,
                              watchedAt: Date) -> TVEpisode {
        let row = TVEpisode(
            episodeNumber: episode,
            seasonNumber: season,
            name: "E\(episode)",
            overview: "",
            isWatched: true,
            showID: showID
        )
        row.watchedDate = watchedAt
        container.mainContext.insert(row)
        return row
    }

    @MainActor
    private func impact() async -> CloudSyncService.SyncImpact {
        await CloudSyncService(modelContainer: container).calculateSyncImpact()
    }

    @discardableResult
    @MainActor
    private func sync(approving pulls: Set<String> = [], uploading: Set<String> = []) async -> CloudSyncService.SyncSummary {
        await CloudSyncService(modelContainer: container).performSelectiveSync(
            approvedImportIDs: pulls,
            approvedUpdateIDs: pulls,
            approvedUploadIDs: uploading,
            syncEpisodes: true
        )
    }

    @MainActor
    private func save() throws { try container.mainContext.save() }

    /// The service applies changes through its own `ModelContext`, so objects held by the test are
    /// stale afterwards — assertions read the store through a fresh context.
    @MainActor
    private func fresh<T: PersistentModel>(_ type: T.Type, where predicate: Predicate<T>) throws -> T? {
        try ModelContext(container).fetch(FetchDescriptor<T>(predicate: predicate)).first
    }

    // MARK: - Watermark

    /// The whole point of the watermark: a library that has not changed costs nothing to sync.
    @MainActor
    func testUnchangedLibraryHasNothingToDo() async throws {
        localMedia(id: "movie_1", lastInteraction: Date().addingTimeInterval(-7200),
                   dateAdded: Date().addingTimeInterval(-7200))
        try save()
        stub.tables["user_media"] = [cloudMedia(
            "movie_1",
            lastInteraction: stamp(-7200),
            updatedAt: stamp(-7200),
            dateAdded: stamp(-7200)
        )]
        setWatermark(-3600)   // newer than the row, so the fetch omits it

        let result = await impact()

        XCTAssertFalse(result.hasChanges, "a row edited before the watermark is not a change")
        XCTAssertTrue(stub.posts(to: "user_media").isEmpty, "nothing to push")
    }

    // MARK: - Media conflicts

    @MainActor
    func testNewerRemoteEditIsAnIncomingUpdate() async throws {
        localMedia(id: "movie_1", state: .active, lastInteraction: Date().addingTimeInterval(-7200))
        try save()
        stub.tables["user_media"] = [cloudMedia("movie_1", state: "Completed",
                                                lastInteraction: stamp(-60), updatedAt: stamp(-60))]
        setWatermark(-7200)

        let result = await impact()

        XCTAssertEqual(result.titlesToUpdate.map(\.id), ["movie_1"], "the newer cloud edit wins")
        XCTAssertTrue(result.titlesToUpload.isEmpty)
    }

    @MainActor
    func testNewerLocalEditIsAnUpload() async throws {
        localMedia(id: "movie_1", state: .completed, lastInteraction: Date().addingTimeInterval(-30))
        try save()
        stub.tables["user_media"] = [cloudMedia("movie_1", state: "Active",
                                                lastInteraction: stamp(-3600), updatedAt: stamp(-3600))]
        setWatermark(-7200)

        let result = await impact()

        XCTAssertEqual(result.titlesToUpload.map(\.id), ["movie_1"], "this device edited last")
        XCTAssertTrue(result.titlesToUpdate.isEmpty)
    }

    /// Android used to write "Loved" where this app writes "Love". That is the same rating, not a
    /// conflict — it used to be reported as one, and the row then flipped back and forth.
    @MainActor
    func testLegacyTasteSpellingIsNotAConflict() async throws {
        localMedia(id: "movie_1", state: .active, tasteValue: "Loved",
                   lastInteraction: Date().addingTimeInterval(-7200))
        try save()
        stub.tables["user_media"] = [cloudMedia("movie_1", taste: "Love",
                                                lastInteraction: stamp(-60), updatedAt: stamp(-60))]
        setWatermark(-7200)

        let result = await impact()

        XCTAssertTrue(result.titlesToUpdate.isEmpty, "canonically equal taste is not a difference")
        XCTAssertTrue(result.titlesToUpload.isEmpty)
        XCTAssertFalse(result.hasChanges)
    }

    /// The failure that stuck a title: a device whose clock ran fast stamped it hours ahead, so
    /// every later edit made here looked older and lost. Bounded, the local edit wins again.
    @MainActor
    func testAFutureStampedRowDoesNotOutrankALaterLocalEdit() async throws {
        localMedia(id: "movie_1", state: .completed, lastInteraction: Date())
        try save()
        stub.tables["user_media"] = [cloudMedia(
            "movie_1",
            state: "Active",
            lastInteraction: stamp(4 * 3600),    // bad clock, four hours ahead
            updatedAt: stamp(-60)                // …but written a minute ago
        )]
        setWatermark(-7200)

        let result = await impact()

        XCTAssertEqual(result.titlesToUpload.map(\.id), ["movie_1"], "the real later edit wins")
        XCTAssertTrue(result.titlesToUpdate.isEmpty)
    }

    @MainActor
    func testASoftDeleteInTheCloudPropagates() async throws {
        localMedia(id: "movie_1", lastInteraction: Date().addingTimeInterval(-7200))
        try save()
        stub.tables["user_media"] = [cloudMedia("movie_1", lastInteraction: stamp(-60),
                                                updatedAt: stamp(-60), softDeleted: true)]
        setWatermark(-7200)

        await sync(approving: ["movie_1"])

        let stored = try fresh(MediaItem.self, where: #Predicate { $0.id == "movie_1" })
        XCTAssertEqual(stored?.isSoftDeleted, true, "a delete made elsewhere has to arrive here too")
    }

    // MARK: - Ledger

    /// The duplicate that showed one episode on two days: the same watch, recorded here under the
    /// legacy episode id and pulled back under the canonical one, stamped 5½ hours apart.
    @MainActor
    func testADuplicateWatchIsNotLoggedTwice() async throws {
        localEpisode(showID: 293610, season: 1, episode: 3,
                     watchedAt: Date().addingTimeInterval(-7200))
        container.mainContext.insert(WatchEvent(
            cycleID: UUID(), mediaID: "tv_293610", episodeID: "293610_1_3",
            watchedAt: Date().addingTimeInterval(-7200), source: .automatic,
            deduplicationKey: "k"
        ))
        try save()

        let cycle = UUID().uuidString
        stub.tables["user_watch_cycles"] = [[
            "user_id": "mt_sync_scenarios", "cycle_id": cycle, "media_id": "tv_293610",
            "kind": "tvShow", "started_at": stamp(-7200), "completed_at": NSNull(),
            "state": "active", "is_rewatch": false, "is_complete": false,
            "scope_episode_ids": [], "is_backfilled": false, "updated_at": stamp(-60)
        ]]
        stub.tables["user_watch_events"] = [[
            "user_id": "mt_sync_scenarios", "event_id": UUID().uuidString, "cycle_id": cycle,
            "media_id": "tv_293610", "episode_id": "tv_293610_s1_e3",   // canonical spelling
            "watched_at": stamp(-7200 + 5.5 * 3600),                    // …and 5½ hours ahead
            "source": "manual", "timezone_identifier": NSNull(),
            "runtime_minutes": NSNull(), "voided_at": NSNull(),
            "deduplication_key": "k", "is_backfilled": false, "updated_at": stamp(-60)
        ]]

        await sync()

        let events = try ModelContext(container).fetch(FetchDescriptor<WatchEvent>())
        let forEpisode = events.filter { $0.episodeID == "293610_1_3" || $0.episodeID == "tv_293610_s1_e3" }
        XCTAssertEqual(forEpisode.count, 1, "one viewing, one event")
    }

    @MainActor
    func testAVoidedRemoteEventIsVoidedLocally() async throws {
        localEpisode(showID: 293610, season: 1, episode: 3,
                     watchedAt: Date().addingTimeInterval(-7200))
        let eventID = UUID()
        container.mainContext.insert(WatchEvent(
            id: eventID, cycleID: UUID(), mediaID: "tv_293610", episodeID: "293610_1_3",
            watchedAt: Date().addingTimeInterval(-7200), source: .manual,
            deduplicationKey: "k"
        ))
        try save()

        let cycle = UUID().uuidString
        stub.tables["user_watch_cycles"] = [[
            "user_id": "mt_sync_scenarios", "cycle_id": cycle, "media_id": "tv_293610",
            "kind": "tvShow", "started_at": stamp(-7200), "completed_at": NSNull(),
            "state": "active", "is_rewatch": false, "is_complete": false,
            "scope_episode_ids": [], "is_backfilled": false, "updated_at": stamp(-60)
        ]]
        stub.tables["user_watch_events"] = [[
            "user_id": "mt_sync_scenarios", "event_id": eventID.uuidString, "cycle_id": cycle,
            "media_id": "tv_293610", "episode_id": "293610_1_3",
            "watched_at": stamp(-7200), "source": "manual", "timezone_identifier": NSNull(),
            "runtime_minutes": NSNull(), "voided_at": stamp(-30),   // voided upstream
            "deduplication_key": "k", "is_backfilled": false, "updated_at": stamp(-30)
        ]]

        await sync()

        let events = try ModelContext(container).fetch(FetchDescriptor<WatchEvent>())
        XCTAssertNotNil(events.first(where: { $0.id == eventID })?.voidedAt, "the void has to arrive")
    }

    /// A date correction used to update the episode projection only — and the year review reads
    /// the ledger, so the corrected time never showed up.
    @MainActor
    func testACorrectedEpisodeDateReachesProjectionAndLedger() async throws {
        let old = Date().addingTimeInterval(-86_400)
        let corrected = old.addingTimeInterval(3600)
        _ = localEpisode(showID: 293610, season: 1, episode: 3, watchedAt: old)
        container.mainContext.insert(WatchEvent(
            cycleID: UUID(), mediaID: "tv_293610", episodeID: "293610_1_3",
            watchedAt: old, source: .manual, deduplicationKey: "k"
        ))
        try save()

        stub.tables["user_episodes"] = [[
            "user_id": "mt_sync_scenarios", "episode_id": "293610_1_3", "show_id": "tv_293610",
            "season_number": 1, "episode_number": 3, "is_watched": true,
            "watched_date": iso.string(from: corrected), "updated_at": stamp(-30)
        ]]
        setWatermark(-7200)

        await sync()

        let storedEpisode = try fresh(TVEpisode.self, where: #Predicate { $0.uniqueID == "293610_1_3" })
        XCTAssertEqual(storedEpisode?.watchedDate?.timeIntervalSince1970 ?? 0,
                       corrected.timeIntervalSince1970, accuracy: 1.0,
                       "the projection follows the cloud")
        let events = try ModelContext(container).fetch(FetchDescriptor<WatchEvent>())
        let event = events.first { $0.episodeID == "293610_1_3" }
        XCTAssertEqual(event?.watchedAt.timeIntervalSince1970 ?? 0,
                       corrected.timeIntervalSince1970, accuracy: 1.0,
                       "and so does the ledger, which the year review reads")
    }

    /// The sync key is the tenant secret. It used to be sent as `user_id=eq.<key>` in every
    /// request URL, which put it into proxy logs, PostgREST access logs and the on-disk
    /// `URLCache`. PostgREST scopes rows by the `x-sync-key` header through RLS, and the
    /// client re-checks the tenant after decoding.
    @MainActor
    func testSyncKeyNeverTravelsInRequestURLs() async throws {
        localMedia(id: "movie_1", state: .active, lastInteraction: Date())
        try save()
        stub.tables["user_media"] = [cloudMedia(
            "movie_1", taste: "Love", lastInteraction: stamp(-60), updatedAt: stamp(-60)
        )]
        setWatermark(-7200)

        _ = await impact()
        _ = await sync()

        XCTAssertFalse(stub.recorded.isEmpty, "the run must have made requests")
        for request in stub.recorded {
            XCTAssertFalse(
                request.query.contains("mt_sync_scenarios"),
                "sync key leaked into a URL: \(request.table)?\(request.query)"
            )
            XCTAssertFalse(
                request.query.contains("user_id=eq."),
                "the tenant filter belongs in the header, not the URL: \(request.query)"
            )
        }
    }
}
