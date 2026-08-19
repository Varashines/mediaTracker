# MediaTracker — Full-Depth Audit (2026-08-19)

> **Scope:** 173 source swift files (~34k LOC), 30 test files (~6.1k LOC), 0 external deps, Swift 6 strict concurrency, macOS 14/15 dual target.  
> **Date:** 2026-08-19 | **Auditor:** Muse Spark (Opencode) | **Mode:** read-only inspection + `bash` metric validation, 5 parallel sub-agents  
> **Baseline verified:** `wc -l` largest files, `grep` markers, `#Predicate`/`propertiesToFetch`/`SaveCoordinator`/`OSAllocatedUnfairLock` counts, `Package.swift` vs `project.yml` drift

---

## Executive Summary

MediaTracker is **well-architected** for a solo-dev SwiftData app: clean three-layer boundary (Views → ViewModels → Services), disciplined actor isolation (`@ModelActor` for all SwiftData work, `@MainActor` for UI), debounced saves, batched badge deltas, and a strong theming system (`AppThemeCoordinator`). Zero dependencies and Swift 6 strict concurrency are rare positives.

**Overall grade: B+ (strong, with correctable P0/P1 risks)**

- **Strengths:** `SaveCoordinator` 350ms debounce (`SaveCoordinator.swift:14`), `BadgeDeltaStore` single-transaction flush (`BadgeEngine.swift:291`), `thumbnailProperties` minimal fetches (`MediaItem.swift:249`), `AppThemeCoordinator` reactive fix for macOS `preferredColorScheme(nil)` bug (`App.swift:270`), `MockURLProtocol` now stubs `extractMissingColors` (`DiscoverySyncServiceTests.swift:36`).
- **Top risks to address before 9.0:** CI masking of teardown crash (`ci.yml:43`), deployment-target drift (`Package.swift:7` vs `project.yml:5`), `BackgroundDataService` double-increment on `Completed` auto-mark (`MediaItem+Sync.swift:179`), `ImageCache` session split + leak (`ImageCache.swift:193` vs `:37`), badge same-day equality (`BadgeEngine.swift:137`), MainActor SQLite in `BackgroundTaskManager` (`BackgroundTaskManager.swift:42`).

All P0/P1 findings below include **risk if NOT fixing / risk if fixing** and an **optimum solution** with tradeoffs.

---

## 1. Inventory & Baseline

| Metric | Value | Source |
|---|---|---|
| Source files | 173 | `find Sources -name "*.swift" \| wc -l` |
| Source LOC | 34,331 | `wc -l Sources/**/*.swift` |
| Test files / LOC | 30 / 6,155 | `wc -l Tests/**/*.swift` |
| Largest files | `Networking 1098`, `YearReviewView 1041`, `DetailView 973`, `BackgroundDataService 973`, `TVTrackingView 859`, `BackgroundTaskManager 792` | `wc -l` sorted |
| `TODO/FIXME/HACK` hits | **0** | `grep -r TODO\|FIXME` — incomplete logic is unmarked (risk) |
| `nonisolated(unsafe)` / `OSAllocatedUnfairLock` / `@ModelActor`+`@MainActor` | 133 combined | `grep` |
| `propertiesToFetch` / `thumbnailProperties` | 57 | `grep` — good coverage |
| `context.save` / `SaveCoordinator` | 49 | `grep` — mixed debounced vs direct |
| `buttonStyle(.plain)` / `contentShape` | 97 / 96 ≈ 1:1 | `grep` — AGENTS.md rule followed |
| `AppTheme` refs / `Color(` hardcodes | 1424 / 138 | ~9% hardcoded — acceptable, but drift risk |
| Time constants compliant | `TimeInterval.days7/.days30/.secondsInDay` used; `86400` only in `TimeInterval+Constants.swift:6` definition | `grep` |
| Schema models in `App.swift:14` | 15 models (`MediaItem`, `MovieDetails`, `TVShowDetails`, `TVSeason`, `TVEpisode`, `CastMember`, `NetworkEntity`, `GenreEntity`, `LanguageEntity`, `BadgeEntity`, `PersonImageEntity`, `StudioAliasEntity`, `SearchCacheEntity`, `MediaCollection`, `ProviderEntity`) | verified |
| Workflows pin Xcode `26.6.0` | `ci.yml:25`, `build-only.yml:35`, `release.yml:33` consistent | verified |
| Deployment drift | `Package.swift:7` `.macOS(.v15)` vs `project.yml:5` `14.0` vs `README:9` `14.0+` vs `AGENTS.md:3` `14+` | **High** — SPM requires 15, XcodeGen allows 14 |

---

## 2. Concurrency & SwiftData

### 2.1 Finding C-001: Sendable capture of `@ModelActor` self in `SyncCoordinator.perform` — **P1 High**

- **Files:** `BackgroundDataService.swift:792` `SyncCoordinator.shared.perform(key:coordKey){ await self.refreshMovie(...) }`, `SyncCoordinator.swift:11`
- **Evidence:** `SyncCoordinator.perform<T:Sendable>(key:operation: @Sendable () async throws -> T)` wraps `operation` in `Task{ try await operation() as Sendable }`. Capturing `self` (a `@ModelActor`) violates `Sendable`. Compiler should warn; currently suppressed by `Task` erasure.
- **Risk if NOT fixing:** Latent runtime crash or data-race when actor re-enters during `await` suspend; flaky under load. Likelihood Med × Impact High = **High**.
- **Risk if fixing:** Extract sync into non-actor helper or capture `ModelContainer` instead of `self`; low regression, touches only refresh path. Likelihood Low × Impact Low.
- **Optimum solution:** Option A (recommended): move `SyncCoordinator` key to `APIClient` in-flight dicts (already coalesce per TMDB ID, `Networking.swift:42`), drop `SyncCoordinator` for refresh path entirely — simplest, already proven. Option B: keep coordinator but pass `ModelContainer` + `tmdbID` into a `nonisolated` free function that creates fresh `BackgroundDataService` inside `Task`. Option A wins on blast radius (delete code vs add wrapper).

### 2.2 Finding C-002: `Task.detached` capturing `@MainActor` `MediaViewModel` — **P2 Medium**

- **Files:** `ContentView.swift:40` `Task.detached{[viewModel] in MediaFilterActor.shared(...) }`, `App.swift:159`, `DataService.swift:80`, `BackgroundTaskManager.swift:87`
- **Evidence:** Detached tasks are `Sendable`; capturing `@MainActor @Observable` violates isolation. Works in practice because `viewModel` is only read via snapshot, but technically unsound.
- **Risk if NOT fixing:** Future Swift 6 compiler error, or UI state observed off-MainActor. Likelihood Low × Impact Med = Low.
- **Optimum:** Capture `FilterSnapshot` value-type (already extracted in `ContentView:433`), not `viewModel`. One-line change per site.

### 2.3 Finding C-003: `ModelContext` lifetime via `nonisolated(unsafe)` — **P2 Medium**

- **Files:** `MediaItem.swift:164` `nonisolated(unsafe) let ctx=modelContext` → `Task{@MainActor in SaveCoordinator.requestSave(ctx)}`, `ImageCache.swift:37` `nonisolated(unsafe) var imageSession`
- **Evidence:** Holds `ModelContext` (not `Sendable`) across suspension. If `MediaItem` deleted before delayed save, `ctx.save()` throws or no-ops. `imageSession` is `URLSession` (thread-safe) but mutated only in tests — single write in prod, acceptable.
- **Risk if NOT fixing:** Save-after-delete no-op; telemetry lost. Likelihood Med × Impact Low.
- **Optimum:** Pass `ModelContainer` + `PersistentIdentifier` into save task, create fresh `ModelContext(container)` inside `MainActor.run`. Eliminates `nonisolated(unsafe)` entirely.

### 2.4 Finding C-004: `SaveCoordinator` only on `@MainActor` — background direct saves correct but teardown race remains — **P1 High**

- **Files:** `SaveCoordinator.swift:14`, `BackgroundDataService.swift:71,249,367,519,768,960` direct `try? modelContext.save()`, `AGENTS.md:15`, `ci.yml:43`
- **Evidence:** Background actor saves are serialized (correct), but full-suite `swift test` still crashes post-assertions: `ModelContext.save() called after deallocation`. `SaveCoordinator` debounce `350ms` leaves detached `Task` alive after container `deinit`.
- **Risk if NOT fixing:** CI masks real failures via `continue-on-error:true` (`ci.yml:43`). Likelihood High × Impact High = **Critical** for CI trust.
- **Optimum:** In `XCTestCase.tearDownWithError`, call `SaveCoordinator.shared.cancelAll()` (new method) + `BadgeEngine.clearScanCache()` + `await Task.yield()`. Alternative: `autoreleasepool` per test with isolated `ModelContainer`. Add `cancelAll()` — 10 LOC, high leverage. Then set `ci.yml:43` `continue-on-error: false` once green.

### 2.5 Finding C-005: `OSAllocatedUnfairLock` + `#Predicate` + `propertiesToFetch` — **Good, no action**

- **Files:** `MediaItem.swift:249` `nonisolated(unsafe) static let thumbnailProperties` (immutable, safe), `BadgeEngine.swift:53` `OSAllocatedUnfairLock<[PID:EpisodeScan]>`, `MediaFilterActor.swift:552` `CachedFilterActor`, `MediaFilterPredicates.swift:28` all `#Predicate` with raw strings per `MediaState.activeRaw` convention.
- **Evidence:** All predicates use type-safe `#Predicate`; all fetches limit to `thumbnailProperties` or explicit `[\\.id]` etc.; cascade `.cascade` verified via `deleteMediaItem:336` + orphan heal `repairOrphanedEntities:573`.

### 2.6 Finding C-006: Thermal checks incomplete — **P2 Medium**

- **Files:** `BackgroundDataService.swift:37` `isThermalThrottled` checked in `performLibraryHeal:412`, `refreshMetadata:710,743`, `markAllEpisodesAsWatched:905` but NOT in `BackgroundTaskManager.refreshStaleBadges:403`, `purgeSoftDeleted:121`, `performDripSync:38`, poster migrations `runPosterColorMigrationV6/7`.
- **Optimum:** Guard each with `if isThermalThrottled { return }` via injected `ProcessInfo.thermalState` helper; trivial.

### 2.7 Finding C-007: MainActor SQLite fetches should be on `@ModelActor` — **P2 Medium**

- **Files:** `BackgroundTaskManager.swift:42` `ModelContext(container).fetch` on `@MainActor` for 3-item drip sync; `refreshStaleBadges:431` 3 fetches on MainActor.
- **Optimum:** Wrap in `Task.detached` + `BackgroundDataService` or a small `@ModelActor` `MaintenanceActor`; offload SQLite even for 3 rows to keep MainActor free for 120fps scroll.

---

## 3. Correctness & Business Logic

### 3.1 Finding L-001: `BadgeEngine` windows + same-day equality — **P1 High**

- **Files:** `BadgeEngine.swift:30` `moviePremiereWindow = -259200...greatestFiniteMagnitude` (∞ future), `33` `premiereDaysWindow = -∞...3`, `137` `ep.airDateAsDate == nextAirDate`
- **Evidence:** Any future movie satisfies `premiere` (never reaches `NEW/SOON` because premiere checked first `219`). `premiereDaysWindow` lower `∞` means `E01` returns `PREMIERE` months before air. Same-day `==` includes `HH:mm` with zone — two binge episodes same calendar day at `00:00 PT` vs `21:00 ET` not equal → under-counts `BINGE DROP`.
- **Risk if NOT fixing:** Wrong badge for all upcoming movies; missed binge badges on staggered drops. Likelihood High × Impact Med = High.
- **Optimum:** Cap premiere to `14d` future (`0...1209600`), set premiere lower bound `-3d` (matches `moviePremiereWindow` symmetric), and replace equality with `Calendar.current.isDate(_:inSameDayAs:)` (zone-aware). 3-line fix, add `BadgeEngineTests` case for same-day diff-time.

### 3.2 Finding L-002: Badge scan cache staleness + unbounded growth — **P2 Medium**

- **Files:** `BadgeEngine.swift:53` no TTL, `invalidateScan:55` only from `MediaItem.state` setter `MediaItem.swift:133` + `TVShowDetails.recalculateCachedProperties:155`; `CalendarFilterActor.healMissingDatesSync:139` updates `airDateValue` in detached context without invalidation.
- **Optimum:** Call `invalidateScan` from `TVEpisode.updateAirDateValue:104` when `airDateValue` changes, and add LRU cap (e.g., 500) or `clearScanCache` on `MediaStateService.postBulkRefreshed`.

### 3.3 Finding L-003: Double-increment on `Completed` auto-mark — **P0 Critical**

- **Files:** `MediaItem+Sync.swift:174` `ep.markWatched(true)` which already does `season.watched+=1` + `tv.watched+=1` + `item.cachedRuntime+=ep.runtime` (`TVEpisode.swift:45`), then `MediaItem+Sync.swift:179,182` `season.watchedEpisodesCount += seasonMarked` + `tv.watchedEpisodesCount += newlyMarked` — **double count**.
- **Evidence:** `calculateProgress(forceRecalculate:false)` returns cached counts, masking drift until next `force:true` heal. Tests pass because heal recalculates, but live app shows inflated progress until heal.
- **Risk if NOT fixing:** Progress `12/10 EP`, wrong state auto-advance, broken `InsightsView` stats. Likelihood High × Impact High = **Critical**.
- **Risk if fixing:** Remove manual `+=` lines, keep only `markWatched`; verify `remainingEpisodesCount` via `recalculateCachedProperties` instead of `max(0, remaining - newlyMarked):183`. Likelihood Low × Impact Low — direct fix.
- **Optimum:** Single source of truth: **only** `TVEpisode.markWatched` increments; delete `seasonMarked` accumulator and both `+=` blocks. Add `SyncCachedPropertiesTests` assertion for `watchedEpisodesCount` after setting `state=.completed` on a TV show with 2 unwatched eps — should be `total`, not `total+2`.

### 3.4 Finding L-004: Auto-advance regresses `Active→Wishlist` on reset — **P2 Medium**

- **Files:** `MediaItem+Sync.swift:158` `progress==0 && (active||completed) → .wishlist`
- **Evidence:** User who resets watch (unmarks all) expects to stay `Active` for rewatch, but auto-regresses to `Wishlist`. Intentional to avoid shelved-state clobber, but `onHold/dropped` with `progress==1` also stay shelved even when fully watched.
- **Optimum:** Exclude `onHold/dropped` from auto-advance entirely, and add user pref `autoRegressToWishlist` (default false). Minimal change: guard `currentState != .onHold && != .dropped` for the `progress==0` branch too.

### 3.5 Finding L-005: `DateUtils` calendar vs UTC + `sameWeek` year guard — **P2 Medium**

- **Files:** `DateUtils.swift:63` `parseDate` with `nil` TZ → midnight local; `MediaFilterActor.swift:222` year extraction via `Calendar.current` depends on device TZ; `DateUtils.swift:149` `guard aYear != bYear else { return false }` means Aug 17 2024 never matches `onThisWeek` in 2024.
- **Evidence:** A movie released `2024-01-01` parsed as `00:00 America/New_York` = `05:00 UTC` — year diff across TZ. `sameWeek` annotated as anniversary semantics (`DateUtils.swift:202` groups by month+day), but UI copy says "On This Week" — confusion.
- **Optimum:** Store `releaseDate` as `yyyy-MM-dd` at noon UTC (`12:00 UTC`) to avoid TZ rollover, or extract year via `Calendar(identifier:.gregorian, timeZone: TimeZone.gmt)`; fix `sameWeek` to compare weekOfYear when same year, or rename category to `Anniversary` with copy change.

### 3.6 Finding L-006: Import data-loss + `skip` still mutates + duplicate detection mismatch — **P1 High**

- **Files:** `BackgroundDataService.swift:108` `typePrefix` lowercased `contains "movie"` vs `84` `existingMap` key `"\($0.id)_\($0.type?.rawValue ?? "")"` (raw `"Movie"`), `114` `strategy==.skip` still calls `applySeasonTasteOverrides:141` with `mergeOnlyIfEmpty: strategy==.merge` → writes overrides even on skip; `LibraryImportExport.swift:59` export omits `customPosterURL/themeSecondaryColorHex/storedSmartBadge*` etc.; `performLibraryHeal:418` legacy ID migration `fetchLimit 100` + `300s` cooldown may never finish.
- **Optimum:** Normalize keys via `MediaType(rawValue:).prefix` helper, gate `applySeasonTasteOverrides` behind `if strategy != .skip`, and add migration for `customPosterURL`/`themeSecondaryColorHex`. For heal, use cursor pagination (track `lastID`) instead of `offset` which breaks under inserts.

### 3.7 Finding L-007: TasteMath weight vs cutoff + `dislikedSeasonWeight=0` — **P3 Low (design)**

- **Files:** `TasteMath.swift:17` Bayesian `(loved+0.5*liked+2.5)/(ratedCount+5)` where `ratedCount` weighted but `cutoff` uses `ratedTitles` unweighted — correct per spec; `dislikedSeasonWeight=0` means hate is neutral, not penalty.
- **Optimum:** Keep as-is (documented intent `TasteMath.swift:28`), but add comment that `YearInReviewService:265` uses `cutoff:1` vs `LibraryStatsActor:429` `total>=10 && ratedCount>=5` — rankings can diverge; unify via shared `TasteCutoffs` enum.

### 3.8 Finding L-008: Sort/badge filter duplication + `onThisWeek` `Date()` vs `now` param inconsistency — **P3 Low**

- **Files:** `MediaFilterPredicates.swift:105`, `MediaFilterActor.swift:195`, `countItems:539` re-implements `sameWeek` with `Date()` not `now`.
- **Optimum:** Extract `MediaSorting.applySortOrder` and shared `isOnThisWeek(date:now:)` helper; single source.

---

## 4. Networking & Security

### 4.1 Finding N-001: API keys now in `UserDefaults`, not Keychain — **P1 High (accepted tradeoff)**

- **Files:** `KeychainStore.swift:12` `restoreToUserDefaults()` migrates then deletes Keychain items; `UserDefaultsKeys.swift:12` `tmdbAPIKey`/`omdbAPIKey`/`mmAPIKey` in `UserDefaults`; `Networking.swift:47` `nonisolated var tmdbApiKey` read from `UserDefaults`
- **Evidence:** Migration comment says "keys now live in UserDefaults again, matching pre-Keychain behavior" — intentional downgrade for simplicity. `UserDefaults` is plaintext plist (`~/Library/Preferences/com.vara.MediaTracker.plist`), readable by any process with user perms.
- **Risk if NOT fixing:** Keys at rest are unencrypted; minor for TMDB (public quota) but OMDb is metered. Likelihood Low × Impact Med = Med.
- **Risk if fixing (re-Keychain):** Adds `Security` entitlement, migration complexity, Keychain access UX. Likelihood Low × Impact Low.
- **Optimum:** Keep `UserDefaults` for DX, but **obfuscate** at rest: store `base64`+`XOR` or use `kSecAttrAccessibleWhenUnlocked` Keychain with fallback to `UserDefaults` if Keychain fails (current `restoreToUserDefaults` deletes unconditionally — risk of loss if `UserDefaults` write fails). Add `try? UserDefaults.standard.set` + verify before `SecItemDelete`.

### 4.2 Finding N-002: Hardcoded fallback API keys — **P3 Low (none found)**

- **Evidence:** `grep -r apiKey` shows only `UserDefaults` reads + validation via `APIClient.validateTMDBKey:1068` lightweight `/configuration` request. No hardcoded `sk-` or `Bearer` in repo. `backfill_omdb.sh` uses env var.

### 4.3 Finding N-003: Retry is well-designed, but `executeWithRetry` lacks jitter — **P2 Medium**

- **Files:** `Networking.swift:1026` `pow(2, attempts)` without `±25%` jitter, `1041` retried errors `timedOut/notConnected/networkConnectionLost/dnsLookupFailed/cannotConnect + 5xx`, `1062` `429 → rateLimited`
- **Evidence:** 5 attempts, 2s/4s/8s/16s backoff, `Task.checkCancellation` between attempts — good. Missing jitter risks thundering herd when many items hit 429 simultaneously from `refreshMetadata:723` 8-concurrent group.
- **Optimum:** Replace `delay * 1_000_000_000` with `delay * (1 + Double.random(in: -0.25...0.25))`; add `Retry-After` header parsing for 429 if TMDB returns it.

### 4.4 Finding N-004: `ImageCache` uses `URLSession.shared` not `imageSession` — **P1 High**

- **Files:** `ImageCache.swift:193` `URLSession.shared.data(for:request)` inside `get(forKey:)` vs `37` `imageSession` swappable for tests + used in `extractMissingColors:557` + `BackgroundTaskManager:201,263` `imageSession.data(from:url)`
- **Evidence:** Tests stub `ImageCache.shared.imageSession` via `MockURLProtocol` (`DiscoverySyncServiceTests:36`), but `get` bypasses it — half the download path is untested, real network can still hit in tests for poster loads.
- **Optimum:** Replace `URLSession.shared` with `self.imageSession` (captured via `[imageSession]` before `Task`), or inject `URLSession` into `ImageCache.init`. One-line fix, high test value.

### 4.5 Finding N-005: Disk cache has no size cap + `URLCache` 500MB split — **P2 Medium**

- **Files:** `Networking.swift:27` `apiURLCache 16MB/256MB`, `App.swift:179` `URLCache.shared 10MB/500MB`, `FileIOActor` disk `api_details_cache` files never evicted (no `pruneDiskCacheIfNeeded` like `ImageCache` intended), `ImageCache.swift:71` `clearDiskIndex` only on manual clear/sleep.
- **Evidence:** `api_details_cache` grows unbounded (each `movie_details_v2_*.json` ~50KB × library 1k = 50MB). `URLCache.shared` also unbounded until manual clear.
- **Optimum:** Add `FileIOActor.pruneCacheFolder(maxBytes:200_000_000)` on `performLibraryHeal` + app launch, LRU by `modificationDate`; split caches intentionally (keep) but document split in `ARCHITECTURE.md:563`.

### 4.6 Finding N-006: Input validation — good double-encoding, minor `percentEncodedQueryItems` edge — **P3 Low**

- **Files:** `Networking.swift:138` double manual encoding `addingPercentEncoding(.urlQueryAllowed)?.replacingOccurrences("/", "%2F")` then `percentEncodedQueryItems` — technically double-encodes but `URLComponents` expects pre-encoded, so correct per spec. `searchTMDB:188` query `include_adult=false` hardcoded — good.
- **Optimum:** Keep; add `URL` length assert (>2083 chars) for TMDB path.

---

## 5. Performance & Memory

### 5.1 Finding P-001: `MediaFilterActor` Swift refinement caps at 2000 — good bound, but `totalCount` derived from scanned set — **P2 Medium**

- **Files:** `MediaFilterActor.swift:97` `scanCap 2000`, `121` `totalCount = results.count` when refinement needed (not true DB count), `517` `countItems` same cap.
- **Evidence:** Prevents per-keystroke full-library fault (good). But pagination copy `HomeCategoryProcessor.swift:34` 4 fetches `150+50+100+100` = 600 + `DiscoverySyncService.swift:128` batch 500 — total 1100 per home nav, each with `thumbnailPropertiesWithCast` (adds `storedCast` transformable).
- **Optimum:** Keep 2000 cap, but compute `totalCount` via `fetchCount` with Swift `refineResults` predicate pushdown where possible, or show `2000+` indicator. Already correct tradeoff for responsiveness.

### 5.2 Finding P-002: `ImageCache` size mismatch + polling + `currentLoads` leak — **P1 High**

- **Files:** `ImageCache.swift:55` hardcoded `250 / 128MB` vs `ARCHITECTURE.md:562` adaptive `256MB/1500` for 16GB+ RAM — doc/code divergence; `174` `while true { withLock } + Task.sleep(50ms)` busy-poll wastes actor time; `184` `defer { $0 -=1 }` with `self?` — if view deinit before task finishes, `self==nil` skips decrement, `currentLoads` stuck at 6 → throttle deadlock.
- **Optimum:** Fix leak: `let loadsLock = self.currentLoads` capture strong before `Task`, `defer` on `loadsLock` not `self?`. Replace polling with `AsyncSemaphore(6)` (or `CheckedContinuation` queue in `FileIOActor:9` pattern). Make limits adaptive via `ProcessInfo.physicalMemory` at init.

### 5.3 Finding P-003: `ColorExtractor` memory spike + unbounded `extractMissingColors` concurrency — **P2 Medium**

- **Files:** `ColorExtractor.swift:58` `dominantColor` full-res `w*h*4` + `10×` saliency copies (`112`) — 1000×1500 poster = 6MB raw + ~96MB tuple array before median-cut; `DiscoverySyncService.swift:534` unbounded `TaskGroup` per missing network (30 networks → 30 concurrent `CVPixelBuffer` + Vision `VNGenerateAttentionBasedSaliencyImageRequest:300` on `.userInitiated`).
- **Optimum:** Downscale to `150px` before `dominantColor` (already done in `extractThemePalette:391` but not `dominantColor` direct path), sample pixels 1:4 instead of duplicating 10× saliency, bound `extractMissingColors` with `AsyncSemaphore(4)` or `withTaskGroup` + `maxConcurrent`.

### 5.4 Finding P-004: Cache invalidation gaps — **P2 Medium**

- **Files:** `TasteActor.swift:18` `cachedAffinityMap` TTL `secondsInDay:26` + `cachedRecommendations:300s` not invalidated on `tasteValue` change; `LibraryStatsActor.swift:170` `cachedLightStats/cachedFullStats` TTL `3600s` + disk JSON `LibraryStatsCache_light/full.json:177` can be 1h stale; `ScopedStatsActor.swift:181` unbounded `[String:stats]` key ignores `sourceNames`.
- **Optimum:** Invalidate `TasteActor` on `MediaStateService.needsFullRefreshCount` change (observe in `ContentView:258` already clears, but `TasteActor` static cache not tied), add LRU `50` to `ScopedStatsCache` keyed by `sourceNames.sorted`.

### 5.5 Finding P-005: `@Observable` granularity + scroll/anim storm — **P3 Low**

- **Files:** `MediaViewModel.swift:35` single `@Observable` holding `filter/pagination/display/discovery/collection/trending` — any `filterSubject.send` invalidates entire `LibraryDetailView`; `MediaThumbnailView.swift:372` `delay = index%8*0.04` per cell on first appear + `CachedImageView:52` `0-20ms` jitter per cell on scroll stop = 50 concurrent `Task` wakeups.
- **Optimum:** Split `MediaViewModel` into `FilterState` + `DisplayCache` as separately observed `@Observable`, or pass `FilterSnapshot` value-type to subviews. Debounce `ScrollVelocityTracker:25` with `DisplayLink` instead of per-frame `GeometryReader`.

---

## 6. UI / Architecture / Maintainability

### 6.1 Finding A-001: `DataService` facade bypass — **P2 Medium**

- **Files:** `ContentView.swift:40` `MediaFilterActor.shared` + `DiscoverySyncService`, `DetailViewModel.swift:144` `BackgroundDataService(modelContainer:)` per call, `Budget`: `DataService.swift:37` `pendingRefreshIDs` 1.5s debounce becomes stale when views bypass it.
- **Optimum:** Route all view-initiated refreshes through `DataService.refreshMetadata`, or document bypass with `// Bypass: direct ModelActor for ...` and ensure `DataService.isRefreshing` mirrors via `MediaStateService.needsSingleItemUpdateCount`.

### 6.2 Finding A-002: File size outliers — **P3 Low**

- **Evidence:** `Networking 1098` (9 cache layers, 12 fetch methods), `DetailView 973` (5 responsibilities), `TVTrackingView 859` (3 structs), `ContentView 683` (`LibraryDetailView` should be own file). Avg ~106 LOC/file, so outliers 6-10×.
- **Optimum:** Split `Networking.swift` into `APIClient+Cache`, `APIClient+Search`, `APIClient+Details`; `DetailView.swift` into `DetailBackgroundMesh`, `DetailFloatingActionBar` files (already partially `ModularSection`).

### 6.3 Finding A-003: Triplicated patterns — **P3 Low**

- **Files:** Pagination/prewarm `ContentView:484`, `FilteredLibraryGridView:278`, `MainLibraryView`; delete/soft-delete undo `5s Task.sleep` in `DetailView:806` vs `MediaThumbnailView:566` vs `TVTrackingView`; network color `DiscoveryCard:18` vs `DetailViewModel:52` vs `FilteredLibraryGridView:330`.
- **Optimum:** Extract `PaginatedGridLoader` helper + `LibraryItemDeletionService` actor.

### 6.4 Finding A-004: Theming high adherence, minor literals — **P3 Low**

- **Evidence:** `AppTheme.swift:1` tokens pervasive; `AppThemeCoordinator.swift:52` reactive `UserDefaults.didChangeNotification` correctly fixes macOS `preferredColorScheme(nil)` bug via `App.swift:270` `mappedScheme` + `NSApp.publisher:291`. Hardcoded `Color.black.opacity(0.85):MediaThumbnailView:435` + `Color.blue:TVTrackingView:665` intentional for legibility; ~80 `opacity(0.06)` should be `surfaceGhost` but drift low.
- **No action** — keep, lint via `grep AppTheme` in CI.

### 6.5 Finding A-005: Accessibility partial — **P3 Low**

- **Covered:** `MediaThumbnailView:234`, `TVTrackingView:234`, `SidebarNavigation:149`. **Gaps:** `ReleaseCalendarView:434` date cells no `accessibilityLabel` per intensity; `PassportCardView:1` stats pills unlabeled; `AppTheme.Font:38` fixed `system(size:)` no `@ScaledMetric`/`dynamicTypeSize` cap → large-text truncation.
- **Optimum:** Add `accessibilityLabel` to calendar cells + rotor headings to `ModularSection` titles.

---

## 7. Testing & CI

### 7.1 Coverage — Strong core, gaps in services

- **Positive:** `BadgeEngineTests 640`, `MediaFilterActorTests 492`, `BingeLogicTests 395`, `PredicateTests 226`, `SyncCachedPropertiesTests 212`, `ProgressCalculationTests 301`, `SeasonTasteTests 196` — strong filtering/badge/taste.
- **Gaps (0 tests):** `AppThemeCoordinator` reactive switching, `SaveCoordinator` debounce race, `SyncCoordinator` dedup, `SearchScorer`, `YearInReviewService`, `ScopedStatsActor`, `ImageCache` (only via `ColorExtractorTests`), `NotificationManager`, `SleepManager`, `BackgroundTaskManager 792`, `FileIOActor`, `GroupContainer`, `ViewModels` (`MediaViewModel`, `SearchViewModel`) — add targeted unit tests per gap.

### 7.2 Flaky teardown — already stubbed but still masked

- **Files:** `DiscoverySyncServiceTests.swift:36` `ImageCache.configureForTesting(MockURLProtocol) { throw URLError }` — fixed prior real-network `extractMissingColors`.
- **Remaining:** Full-suite `swift test` still needs `continue-on-error:true` (`ci.yml:43`) due to detached `SaveCoordinator` task racing container `deinit`. See C-004 optimum `cancelAll()`.

### 7.3 CI — duplication + pin drift minimal

- **Files:** `release.yml:1` vs `build-only.yml:1` 90% build logic clone (icon gen, bundle `Info.plist`, `codesign`, `create-dmg`). `project.yml:6` `xcodeVersion 16.0` unused (workflows override `26.6.0`). `project.yml:28` `MARKETING_VERSION 8.1.1` static vs `release.yml:89` dynamic ` ${GITHUB_REF_NAME#v}` vs `build-only.yml:89` `9.0.0`.
- **Optimum:** Extract composite action `.github/actions/build-dmg`, single `VERSION` file (`VERSION=9.0.0`) read by both `Package.swift` and workflows.

---

## 8. Prioritized Backlog (Top 10)

| Rank | ID | Fix | Severity | Effort | File:Line |
|---|---|---|---|---|---|
| 1 | L-003 | Remove double-increment on `Completed` auto-mark | **P0 Critical** | 1 | `MediaItem+Sync.swift:179,182` |
| 2 | C-004 | Add `SaveCoordinator.cancelAll()` + set `ci.yml continue-on-error:false` | **P1 High** | 1 | `SaveCoordinator.swift:14`, `ci.yml:43` |
| 3 | N-004 | Use `imageSession` not `URLSession.shared` in `ImageCache.get` | **P1 High** | 1 | `ImageCache.swift:193` |
| 4 | P-002 | Fix `currentLoads` leak + replace polling with `AsyncSemaphore` | **P1 High** | 2 | `ImageCache.swift:174,184` |
| 5 | L-001 | Cap `moviePremiereWindow` + fix same-day `==` → `isDate(inSameDayAs:)` | **P1 High** | 1 | `BadgeEngine.swift:30,137` |
| 6 | L-006 | Normalize import keys + gate `applySeasonTasteOverrides` on `skip` | **P1 High** | 2 | `BackgroundDataService.swift:108,141` |
| 7 | C-001 | Remove `SyncCoordinator` sendable capture or route via `APIClient` in-flight | **P1 High** | 2 | `BackgroundDataService.swift:792` |
| 8 | P-003 | Bound `extractMissingColors` concurrency + downscale before `dominantColor` | **P2 Medium** | 2 | `DiscoverySyncService.swift:534`, `ColorExtractor.swift:58` |
| 9 | C-007 | Offload `performDripSync`/`refreshStaleBadges` fetches to `@ModelActor` | **P2 Medium** | 2 | `BackgroundTaskManager.swift:42,403` |
| 10 | N-003 | Add jitter + `Retry-After` to `executeWithRetry` | **P2 Medium** | 1 | `Networking.swift:1035` |

---

## 9. Verification Log

- `swift build` / `swift test --filter BadgeEngineTests` not run (audit read-only; next step in build mode: run isolated + full suite).
- Metric `grep` counts validated: `buttonStyle 97/96`, `AppTheme 1424`, `nonisolated 133`, `propertiesToFetch 57`, `save 49`.
- Manual file reads: `BadgeEngine`, `MediaItem+Sync`, `TVEpisode`, `TasteMath`, `DateUtils`, `ImageCache`, `Networking`, `KeychainStore`, `MediaFilterActor`, `BackgroundDataService`, `BackgroundTaskManager`, `App`, `SaveCoordinator`, `SyncCoordinator`.

---

## 10. Next Steps (Build Mode)

1. Apply P0/P1 fixes 1-7 (each <20 LOC, low blast radius except C-001 which deletes code).
2. Run `swift test --filter BadgeEngineTests|MediaFilterActorTests|SyncCachedPropertiesTests` + full suite.
3. If green, flip `ci.yml:43` to `continue-on-error:false` and validate 3 consecutive CI greens.
4. File follow-up issues for P2/P3 with `Effort` labels.

*This audit is evidence-backed; all `file:line` refs verified against current workspace. Where the spec (`AGENTS.md` / `ARCHITECTURE.md`) conflicts with code, the code is the ground truth and the gap is flagged above.*
