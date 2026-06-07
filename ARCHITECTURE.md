# MediaTracker — Architecture & Design Document

> Native macOS media tracking app built with SwiftUI + SwiftData.  
> Targets macOS 15+, Swift 6.0 strict concurrency. Zero external dependencies.  
> 141 source files, 19 test files, ~15,000 LOC source, ~4,000 LOC tests.

---

## 1. Overview

### 1.1 What It Does

MediaTracker lets users maintain a personal library of movies and TV shows. It syncs metadata from TMDB (The Movie Database), enriches ratings from OMDB, and obtains air schedules from TVMaze. The app provides:

- **Library management**: Organize media by state (Wishlist, In Progress, Completed, etc.), taste (Love/Like/Dislike), and custom collections
- **Smart badging**: Auto-calculated badges (PREMIERE, FINALE, BINGE DROP, NEW, SOON, BEHIND, BINGE) based on air dates and watch behavior
- **Discovery hub**: Browse your library by network, genre, language, or badge with aggregated counts
- **Taste profiling**: Personalized affinity maps from your ratings, driving a "For You" recommendation carousel
- **Library insights**: Analytics dashboard with genre DNA, watch history, decade distribution, and talent rankings
- **Release calendar**: Monthly view of upcoming episodes and movies with streaming service time rules
- **Background sync**: Thermal- and power-aware periodic metadata refresh, library heal, and notification scheduling
- **Sleep mode**: Auto-detects user inactivity (60s idle, 120s sleep), dims UI, supresses background work
- **Search**: Local library search + TMDB search with result import

### 1.2 Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI (`NavigationSplitView`, `LazyVGrid`, matched geometry, transitions) |
| Persistence | SwiftData (`@Model`, `#Predicate`, `FetchDescriptor`, `ModelActor`) |
| Concurrency | Swift 6 actors (`actor`, `@ModelActor`, `@MainActor`), `TaskGroup`, unstructured tasks |
| Networking | `URLSession` with custom `Actor`-based client, retry with exponential backoff, response caching |
| Image Handling | `NSCache` (memory) + file system (disk) with `CGImageSource` downsampling |
| State Management | `@Observable @MainActor` view models (not `ObservableObject`), `PassthroughSubject` for 1:N broadcasts |
| Color | OKLCH color space via Core Image histogram analysis for poster/network theme colors |
| Haptics | `NSHapticFeedbackManager` for interaction feedback |
| Scheduling | `UNUserNotificationCenter` for episode/movie release notifications |
| Background | `NSBackgroundActivityScheduler` for periodic maintenance (6-hour cycle) |

### 1.3 Project Structure

```
Sources/MediaTracker/
├── App.swift                      # Entry point, ModelContainer, theme, scene phase
├── ContentView.swift              # Main nav split + library detail orchestrator
├── Models/                        # 16 files — all @Model + transport types
│   ├── MediaItem.swift            # Core model (40+ properties, relationships)
│   ├── MediaItem+Sync.swift       # Cache sync logic
│   ├── TVShowDetails.swift        # TV show metadata + progress calculation
│   ├── MediaModels.swift          # MovieDetails, TVSeason, API response structs
│   ├── TVEpisode.swift            # Episode model with watch propagation
│   ├── MediaCollection.swift      # User collections (manual + smart rules)
│   ├── EntityModels.swift         # Discovery entities, StudioAlias, SearchCache
│   ├── CastMember.swift           # Cast relationship model
│   ├── Enums.swift                # All domain enums (20 categories, states, taste)
│   ├── SmartRules.swift           # Smart collection rule enum
│   ├── MediaThumbnailMetadata.swift  # View-model snapshot struct
│   ├── DiscoveryModels.swift      # Discovery hub value types
│   ├── CommonModels.swift         # API result wrappers
│   ├── TMDBModels.swift           # TMDB API response types
│   ├── TVMazeModels.swift         # TVMaze API response types
│   └── TimeInterval+Constants.swift  # Named time intervals
├── Services/                      # 42 files — all business logic
│   ├── BackgroundDataService.swift       # @ModelActor: heavy mutations
│   ├── BackgroundDataService+Refresh.swift  # TMDB/OMDB refresh extension
│   ├── MediaFilterActor.swift            # @ModelActor: query engine
│   ├── MediaFilterPredicates.swift       # #Predicate builders
│   ├── MediaSorting.swift                # Sort logic
│   ├── MediaGrouping.swift               # Group logic
│   ├── HomeCategoryProcessor.swift       # Home screen data assembly
│   ├── APIClient (Networking.swift)      # Actor: TMDB/OMDB/TVMaze
│   ├── DataService.swift                 # @MainActor facade
│   ├── BadgeEngine.swift                 # Smart badge computation
│   ├── ImageCache.swift                  # Memory + disk image cache
│   ├── SyncCoordinator.swift             # Task deduplication actor
│   ├── SaveCoordinator.swift             # Debounced save
│   ├── SleepManager.swift                # Inactivity detection
│   ├── BackgroundTaskManager.swift       # Periodic work orchestrator
│   ├── DiscoverySyncService.swift        # Hub entity sync
│   ├── LibraryStatsActor.swift           # Analytics computation
│   ├── TasteActor.swift                  # Taste profile + recommendations
│   ├── TasteMath.swift                   # Affinity calculation math
│   ├── MediaStateService.swift           # Change broadcasting
│   ├── NotificationManager.swift         # UNNotification management
│   ├── MooreMetricsService.swift         # External recommendation API
│   ├── CalendarFilterActor.swift         # Calendar data computation
│   ├── ..., ColorExtractor.swift, FileIOActor.swift, GenreMapper.swift,
│   │   LanguageUtils.swift, DateUtils.swift, PrefetchManager.swift,
│   │   NetworkThemeManager.swift, FeedbackManager.swift, AppLogger.swift,
│   │   AppErrorState.swift, AppTheme*.swift, AppThemeCoordinator.swift,
│   │   SwiftData+Extensions.swift, UIExtensions.swift, UserDefaultsKeys.swift,
│   │   SafeSave.swift, GroupContainer.swift, ScrollOffsetKey.swift,
│   │   ScrollVelocityTracker.swift, BackgroundActionService.swift
│   └── ...
├── ViewModels/                    # 8 files — @Observable state containers
│   ├── MediaViewModel.swift       # Central coordinator
│   ├── FilterState.swift          # Filter/sort state
│   ├── PaginationState.swift      # Offset/limit tracking
│   ├── CollectionState.swift      # Collection selection
│   ├── DisplayCache.swift         # Cached display data
│   ├── DiscoveryCache.swift       # Discovery hub data
│   ├── DetailViewModel.swift      # Detail screen state
│   └── SearchViewModel.swift      # Search state
└── Views/                         # 74 files — SwiftUI views
    ├── ContentView.swift          # Main nav split
    ├── SidebarNavigation.swift    # Sidebar with sections
    ├── MediaThumbnailView.swift    # Universal poster card
    ├── DetailView.swift           # Full detail page
    ├── ... (70 more views)
```

---

## 2. Architecture Pattern

### 2.1 Three-Layer Architecture

The app follows a three-layer architecture with strict isolation boundaries:

```
┌─────────────────────────────────────────────────────────────┐
│                         Views                               │
│  SwiftUI structs, @State, environment, NavigationSplitView  │
│  Observe @Observable view models, never touch ModelContext  │
├─────────────────────────────────────────────────────────────┤
│                      ViewModels                             │
│  @Observable @MainActor classes                             │
│  Own sub-state objects (FilterState, DisplayCache, etc.)    │
│  Call DataService (not BackgroundDataService directly)      │
├─────────────────────────────────────────────────────────────┤
│                       DataService                           │
│  @MainActor @Observable singleton facade                    │
│  Debounces + batches refresh requests                       │
│  Dispatches heavy work to BackgroundDataService             │
├─────────────────────────────────────────────────────────────┤
│                    Background Services                       │
│  @ModelActor actors (own ModelContext)                      │
│  MediaFilterActor (queries), BackgroundDataService (mutations)│
│  APIClient (networking, also an actor)                      │
│  TasteActor, LibraryStatsActor, DiscoverySyncService        │
├─────────────────────────────────────────────────────────────┤
│                    Supporting Services                       │
│  ImageCache (@MainActor), SaveCoordinator, BadgeEngine etc. │
│  SyncCoordinator (actor), SleepManager, BackgroundTaskManager │
│  MediaStateService (broadcasting), NotificationManager      │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Actor Isolation Strategy

The app uses Swift actors to enforce thread safety:

| Isolation | Components | Why |
|---|---|---|
| `@ModelActor actor` | `BackgroundDataService`, `MediaFilterActor`, `TasteActor`, `LibraryStatsActor`, `DiscoverySyncService`, `CalendarFilterActor`, `BackgroundActionService` | Owns a dedicated `ModelContext` for serialized SwiftData access |
| `actor` | `APIClient`, `SyncCoordinator`, `FileIOActor` | Protects mutable state (caches, in-flight task registries) without SwiftData |
| `@Observable @MainActor class` | `DataService`, `MediaViewModel` sub-states, `DetailViewModel`, `SearchViewModel`, `SleepManager`, `BackgroundTaskManager`, `MediaStateService`, `AppErrorState`, `AppThemeCoordinator`, `SaveCoordinator`, `ImageCache`, `NetworkThemeManager`, `PrefetchManager`, `FeedbackManager` | Observability via `@Observable` requires `@MainActor`; these interact with SwiftUI views |
| nonisolated struct/enum | `BadgeEngine`, `TasteMath`, `GenreMapper`, `LanguageUtils`, `DateUtils`, `MediaFilterPredicates` | Pure stateless logic, no mutable state |

### 2.3 Data Flow

```
User action (tap, scroll, type)
  → View calls ViewModel method
    → ViewModel updates @Observable state
      → View reacts via @Observable tracking

OR

User action (tap mark-watched)
  → View calls commitChange() on item
    → syncCachedProperties() runs
    → SaveCoordinator.requestSave() debounces save
    → MediaStateService.postMediaStateChanged() broadcasts
      → View re-fetches via MediaFilterActor.fetchMetadataIfMatches()
```

For heavy operations (refresh, add item):
```
View → DataService → dispatches to BackgroundDataService (@ModelActor)
  → APIClient actor fetches from TMDB/OMDB/TVMaze
  → Creates/updates @Model objects in BackgroundDataService's ModelContext
  → Single modelContext.save() at end
  → MediaStateService.shared.postItemRefreshed() / postBulkRefreshed()
    → ViewModel updates DisplayCache on MainActor
```

---

## 3. Data Layer

### 3.1 SwiftData Models (14 `@Model` classes)

#### 3.1.1 MediaItem — The Core Entity

**File:** `Models/MediaItem.swift` + `Models/MediaItem+Sync.swift`  
**Annotations:** `@Model final class MediaItem: Identifiable`  
**Identity:** `@Attribute(.unique) var id: String` (e.g. `"movie_12345"`, `"tv_67890"`)

**Properties by category:**

| Category | Properties |
|---|---|
| **API Origin** | `title`, `overview`, `posterURL?`, `backdropURL?`, `releaseDate?` |
| **Enum State** | `typeValue` (Movie/TV Show), `stateValue` (Wishlist/Active/Completed/On Hold/Dropped/Re-watching), `tasteValue` (None/Like/Love/Dislike) |
| **Derived** | `themeColorHex?`, `themeColorSourceURL?`, `dateAdded?`, `lastUpdated?`, `lastInteractionDate?`, `lastStateChangeDate?` |
| **Cached – Genres** | `cachedGenres: [String]` (transformable) |
| **Cached – Creators** | `cachedCreators: [String]` (transformable) |
| **Cached – Language** | `cachedLanguage: String?` |
| **Cached – Network** | `cachedNetwork: String?` (comma-normalized, e.g. `"Netflix, Hulu"`) |
| **Cached – Network Logo** | `cachedNetworkLogoPath: String?` |
| **Cached – Airing** | `cachedNextAiringDate: Date?`, `cachedRuntime: Int?`, `cachedEpisodeRuntime: Int?` |
| **Cached – Watch Progress** | `cachedWatchedEpisodeCount: Int?`, `remainingEpisodesCount: Int?` |
| **Badge** | `storedSmartBadgeLabel: String?`, `storedSmartBadgeIsSparkle: Bool` |
| **Upcoming** | `storedIsUpcoming: Bool` |
| **Labels** | `storedNextEpisodeLabel: String?` (e.g. `"S2 E5"`), `storedWatchProgressLabel: String?` (e.g. `"12/24 EP"`), `storedProgress: Double?` (0.0–1.0) |
| **Search** | `searchableText: String` (lowercased concatenation of title + overview + genres + creators + cast names + network + language) |
| **Cast** | `storedCast: [SimpleCastMember]` (Codable, top 15 cast members as value types) |

**Relationships:**

```
MediaItem ── (1) ──→ (0..1) MovieDetails    [.cascade]
MediaItem ── (1) ──→ (0..1) TVShowDetails    [.cascade]
MediaItem ── (*) ──→ (*)   MediaCollection    [default]
```

- `movieDetails: MovieDetails?` — Setter triggers `syncMovieProperties()`
- `tvShowDetails: TVShowDetails?` — Setter triggers `syncTVProperties()`
- `collections: [MediaCollection]` — Inverse: `MediaCollection.items`

**Computed properties:**

| Property | Logic |
|---|---|
| `type: MediaType?` | Get/set wrapper around `typeValue` |
| `state: MediaState?` | Setter updates `lastInteractionDate`, `lastStateChangeDate`, calls `syncCachedProperties()`, triggers auto-mark-episodes for TV Completed |
| `taste: TasteValue?` | Setter updates `lastInteractionDate`, calls `syncCachedProperties()` |
| `displayCast: [SimpleCastMember]` | Returns `storedCast` (thin wrapper) |
| `isUpcoming: Bool` | `(cachedNextAiringDate ?? releaseDate) > Date()` |
| `badgeText: String?` | If upcoming: abbreviated date string via `Date.formatted()` |
| `gridBadgeText: String?` | Alias for `badgeText` |
| `detailBadgeText: String?` | TV: date+time; Movie: date-only |
| `requiresMaintenanceRefresh: Bool` | `lastUpdated > 30 days ago` |

**Static `propertiesToFetch`:**
```swift
// 31 key paths — excludes heavy relationships (movieDetails, tvShowDetails, storedCast)
static let thumbnailProperties: [PartialKeyPath<MediaItem>] = [
    \.id, \.title, \.posterURL, \.backdropURL, \.releaseDate,
    \.typeValue, \.stateValue, \.tasteValue, \.themeColorHex, \.themeColorSourceURL,
    \.lastInteractionDate, \.lastStateChangeDate, \.dateAdded, \.lastUpdated,
    \.cachedGenres, \.cachedCreators, \.cachedLanguage, \.cachedNetwork,
    \.cachedNetworkLogoPath, \.cachedNextAiringDate, \.cachedRuntime,
    \.cachedEpisodeRuntime, \.cachedWatchedEpisodeCount, \.remainingEpisodesCount,
    \.storedSmartBadgeLabel, \.storedSmartBadgeIsSparkle, \.storedIsUpcoming,
    \.storedNextEpisodeLabel, \.storedWatchProgressLabel, \.storedProgress,
    \.searchableText
]
static let thumbnailPropertiesWithCast = thumbnailProperties + [\.storedCast]
```

**Key methods (from `MediaItem+Sync.swift`):**

- **`syncCachedProperties(now: Date, force: Bool)`** — The central cache invalidation method. Called after any state or data mutation. Pipeline:
  1. `BadgeEngine.invalidateScan(for:)` (TV only)
  2. `syncCastCache()` — Fetch `CastMember` by `mediaID` via `#Predicate`, deduplicate by name+character, take top 15, store as `[SimpleCastMember]`
  3. `syncMovieProperties()` — Copy from `movieDetails` → cached fields
  4. `syncTVProperties()` — Copy from `tvShowDetails`, run `calculateProgress()`, auto-advance state (Wishlist → Active → Completed), auto-mark episodes if Completed + preference enabled
  5. `BadgeEngine.calculateBadge(for: self, now: now)` → update `storedSmartBadgeLabel/IsSparkle`
  6. Update `storedIsUpcoming`
  7. `updateSearchableText()` if badge changed or forced

- **`syncMovieProperties()`** — Copies: `cachedGenres`, `cachedCreators`, `cachedLanguage`, `cachedNextAiringDate` (releaseDate), `cachedRuntime`, `cachedNetwork` (normalized), `cachedNetworkLogoPath` (normalized)

- **`syncTVProperties(now: Date, currentState: MediaState, forceRecalculate: Bool)`** — Copies: `cachedGenres`, `cachedCreators`, `cachedLanguage`, `cachedNetwork` (normalized), `cachedNetworkLogoPath` (normalized). Runs `calculateProgress()` for: `cachedRuntime`, `cachedWatchedEpisodeCount`, `remainingEpisodesCount`, `cachedEpisodeRuntime`, `storedProgress`, `storedWatchProgressLabel`, `storedNextEpisodeLabel`, `cachedNextAiringDate`. Auto-advances state based on progress thresholds.

- **`updateSearchableText()`** — Lowercased concatenation: `title + overview.prefix(200) + cachedGenres + cachedCreators + cast names + cachedNetwork + cachedLanguage`

#### 3.1.2 TVShowDetails

**File:** `Models/TVShowDetails.swift`  
**Annotations:** `@Model final class TVShowDetails`

| Property | Type | Notes |
|---|---|---|
| `tmdbID` | `Int` | |
| `tvMazeID` | `Int?` | For schedule lookup |
| `numberOfSeasons`, `numberOfEpisodes` | `Int?` | |
| `status` | `String?` | e.g. "Returning Series", "Ended" |
| `genres` | `[String]` | |
| `network`, `networkLogoPath` | `String?` | |
| `creators` | `[String]` | |
| `timezone` | `String?` | For air date calculation |
| `nextEpisodeDate/Number/Season/Time` | various | Denormalized for O(1) access |
| `totalEpisodesCount`, `watchedEpisodesCount` | `Int` | Denormalized for O(1) progress |
| `voteAverage`, `imdbRating`, `rottenTomatoesScore`, `contentRating` | optional | |
| `remainingEpisodesCount` | `Int?` | |

**Relationships:** `seasons: [TVSeason]` (`.cascade`), `cast: [CastMember]` (`.cascade`)

**Key methods:**
- `calculateProgress(now: Date, forceRecalculate: Bool) -> TVProgressResult` — Iterates sorted seasons (excludes Season 0/Specials), counts total/watched/aired episodes, finds first unwatched episode, updates denormalized counts. Returns `TVProgressResult { totalCount, watchedCount, remainingCount, firstUnwatched: TVEpisode?, totalRuntime }`
- `findFirstUnwatched() -> TVEpisode?` — Uses `#Predicate` + `fetchLimit: 1` for O(1) lookup; falls back to relationship scan
- `recalculateCachedProperties(triggerSync: Bool, force: Bool)` — Calls `calculateProgress()` then `item?.syncCachedProperties()`

#### 3.1.3 TVSeason

**File:** `Models/MediaModels.swift`  
**Annotations:** `@Model final class TVSeason`

| Property | Type | Notes |
|---|---|---|
| `seasonNumber` | `Int` | |
| `name` | `String` | |
| `episodeCount` | `Int` | |
| `airDate` | `String?` | |
| `showID` | `Int?` | |
| `uniqueID` | `String?` | `@Attribute(.unique)`, format: `"\(showID)_\(seasonNumber)"` |
| `watchedEpisodesCount` | `Int` | Denormalized |
| `totalEpisodesCount` | `Int` | Denormalized |

**Relationships:** `episodes: [TVEpisode]` (`.cascade`), `tvShowDetails: TVShowDetails?`

#### 3.1.4 TVEpisode

**File:** `Models/TVEpisode.swift`  
**Annotations:** `@Model final class TVEpisode`

| Property | Type | Notes |
|---|---|---|
| `episodeNumber`, `seasonNumber` | `Int` | |
| `name`, `overview` | `String` | |
| `airDate`, `airstamp` | `String?` | Cleared after parsing to `airDateValue` |
| `airDateValue` | `Date?` | Parsed date |
| `runtime` | `Int?` | |
| `isWatched` | `Bool` | |
| `lastWatchedDate`, `watchedDate` | `Date?` | |
| `showID` | `Int?` | |
| `uniqueID` | `String?` | `@Attribute(.unique)`, format: `"\(showID)_\(seasonNumber)_\(episodeNumber)"` |

**Key method — `markWatched(_ watched: Bool)`:**
Propagates count deltas upward through the model graph:
1. Sets `self.isWatched`, `self.lastWatchedDate` (now if watching, nil if unwatching)
2. Updates `season.watchedEpisodesCount += isWatched ? 1 : -1`
3. Updates `tvShowDetails.watchedEpisodesCount += ...` (only for season > 0)
4. Updates `tvShowDetails.remainingEpisodesCount -= ...` if already aired
5. Updates `item.cachedRuntime += ep.runtime`
6. Badge cache is invalidated

#### 3.1.5 MovieDetails

**File:** `Models/MediaModels.swift`  
**Annotations:** `@Model final class MovieDetails`

| Property | Type |
|---|---|
| `tmdbID` | `Int` |
| `runtime`, `voteAverage` | `Int?`, `Double?` |
| `rottenTomatoesScore`, `imdbRating` | `Int?`, `Double?` |
| `contentRating`, `originalLanguage` | `String?` |
| `genres` | `[String]` |
| `creators` | `[String]` |
| `network`, `networkLogoPath` | `String?` |
| `cast` | `[CastMember]` (`.cascade`) |

#### 3.1.6 CastMember

**File:** `Models/CastMember.swift`  
**Annotations:** `@Model final class CastMember`

`uniqueID: String?` (format: `"\(mediaID)_\(name)_\(characterName)"`), `mediaID: String?`, `name`, `characterName: String`, `profileURL: String?`, `order: Int`

**Relationships:** `movieDetails: MovieDetails?`, `tvShowDetails: TVShowDetails?`

#### 3.1.7 MediaCollection

**File:** `Models/MediaCollection.swift`  
**Annotations:** `@Model final class MediaCollection: Identifiable`

`id: UUID`, `name: String`, `systemImage: String`, `completedItemIDs: [String]`, `notes: String?`, `isPinned: Bool`, `smartRulesData: Data?` (JSON-encoded `[SmartRule]`)

**Computed:** `isSmart: Bool` (smartRulesData != nil), `smartRules: [SmartRule]` (JSON encode/decode)

**Relationships:** `items: [MediaItem]` (many-to-many, inverse: `MediaItem.collections`)

#### 3.1.8 Discovery Entities (EntityModels.swift)

| Model | Unique Key | Key Properties |
|---|---|---|
| `NetworkEntity` | `name` | `logoPath?`, `count: Int`, `themeColorHex?`, `sourceNames: [String]` |
| `GenreEntity` | `name` | `count: Int` |
| `LanguageEntity` | `code` | `count: Int` |
| `BadgeEntity` | `label` | `count: Int` |
| `StudioAliasEntity` | `target` | `sources: [String]`, `preferredLogoSource: String?` |
| `SearchCacheEntity` | `key` | `query`, `type`, `resultsData: Data`, `timestamp: Date` |
| `PersonImageEntity` | `name` | `profileURL: String?` |

### 3.2 Relationship Cascade Chain

```
MediaItem deletion
  └── MovieDetails deletion (.cascade)
       └── CastMember deletion (.cascade)
  └── TVShowDetails deletion (.cascade)
       └── TVSeason deletion (.cascade)
            └── TVEpisode deletion (.cascade)
       └── CastMember deletion (.cascade)
```

### 3.3 API Transport Types (non-persistent)

All value types for JSON decoding. Zero SwiftData involvement.

- **`TMDBMedia` protocol**: `TMDBMovie`, `TMDBTV` — search results with `toSearchResult()` extension that maps genre IDs via `TMDBGenreMap`
- **`TMDBMovieDetailsResponse`**: `runtime`, `genres`, `vote_average`, `credits`, `release_dates`, `production_companies`, `external_ids`
- **`TMDBTVDetailsResponse`**: `number_of_seasons/episodes`, `status`, `networks`, `created_by`, `seasons`, `next_episode_to_air`, `credits` (regular + aggregate)
- **`OMDBResponse` / `OMDBFullData`**: `imdbRating`, `rottenTomatoesScore`, `contentRating`
- **`TVMazeResponse`**: Schedule, timezone, network info for airdate resolution
- **`MovieDetailsResult` / `TVDetailsResult`**: Client wrappers combining TMDB + OMDB data before pushing to `@Model` instances
- **`CastMemberResult`**, `TVEpisodeResult`, `ProductionCompanyResult`: Lightweight value types for intermediate transport

### 3.4 UI Snapshot Types (non-persistent, Sendable)

- **`MediaThumbnailMetadata`** — `Sendable`, `Identifiable`, `Equatable` snapshot extracted from `MediaItem` to cross actor boundaries safely. All display-relevant fields copied at init time. Computed: `versionHash`, `formattedMetadata`.

- **`PaginatedResult`** — Container for library display: `displayed`, `featuredUpcoming`, `recentlyAdded`, `homeContinueWatching`, `spotlightHero`, `grouped`, `totalCount`

- **`DiscoveryNode` / `DiscoveryHubData`** — Network/genre/language/badge aggregation for the discovery hub UI

- **`SimpleCastMember`** — `Codable` value type stored inside `MediaItem.storedCast` to avoid faulting the `CastMember` relationship

---

## 4. Services Layer

### 4.1 Data Sync Services

#### BackgroundDataService (`@ModelActor`)

**Role:** The heavyweight workhorse. All deep, multi-entity mutations of the `MediaItem` graph.

**Actor Isolation:** `@ModelActor actor` — owns dedicated `ModelContext`. Writes serialized, but async network calls release the actor for parallel I/O.

**Key Methods:**

| Method | Purpose |
|---|---|
| `createNewMediaItem(uniqueID:tmdbID:type:title:...)` | Uniqueness check, insert, immediate TMDB refresh, `syncCachedProperties()`, save. Returns `(PersistentIdentifier, isExisting)`. |
| `importLibraryData(backup:)` | Batch import `LibraryBackup`. Creates stub `TVEpisode` for watched episodes. Single save at end. |
| `deleteMediaItem(id:)` | Cascade-delete via SwiftData (`modelContext.delete`), purge `ImageCache` for poster URLs. |
| `clearDatabase()` | Wipe all model types: `MediaItem`, `NetworkEntity`, `GenreEntity`, `LanguageEntity`, `MediaCollection`. Clear caches. |
| `performLibraryHeal()` | Core maintenance: (1) repair orphaned TVSeason/TVEpisode, (2) migrate legacy IDs, (3) recalculate progress, (4) auto-mark completed-show episodes, (5) purge stale search cache, (6) reschedule notifications, (7) run `DiscoverySyncService.syncLibrary`. Rate-limited (300s). Thermal-aware. |
| `refreshMetadata(for:metadataOnly:force:)` | Batch refresh with 8-way `TaskGroup`. Checks thermal state mid-batch. Single save at end. |
| `refreshSingleItem(id:metadataOnly:force:shouldSave:)` | Wraps `refreshMovie`/`refreshTVShow` inside `SyncCoordinator.perform(key:)` to deduplicate. Schedules notifications. |
| `markAllEpisodesAsWatched(itemID:)` | Deep completion: force-refresh TV details, pre-fetch missing season details concurrently, populate episodes, mark watched, recalculate, save. |

**Refresh pipeline (`BackgroundDataService+Refresh.swift`):**

```
refreshMovie(id:tmdbID:force:)
  1. APIClient.fetchMovieDetails(tmdbID)
  2. APIClient.fetchOMDBData(imdbID)  [skip if wishlist + no taste]
  3. Upsert MovieDetails (create or update)
  4. Upsert CastMember (diff new vs existing)
  5. extractAndSavePosterColor(posterURL)  [download + histogram]
  6. item.syncCachedProperties(force: true)

refreshTVShow(id:tmdbID:metadataOnly:force:)
  1. APIClient.fetchTVDetails(tmdbID)
  2. TVMaze lookup (only if active)
  3. Upsert TVShowDetails
  4. Upsert CastMember (aggregate credits, diff)
  5. Fetch seasons from TMDB via TaskGroup (parallel)
  6. Create/update TVSeason and TVEpisode per season
  7. recalculateCachedProperties on TVShowDetails
  8. item.syncCachedProperties(force: true)
  9. extractAndSavePosterColor(posterURL)
```

**Thermal Awareness:**
```swift
var isThermalThrottled: Bool {
    ProcessInfo.processInfo.thermalState == .serious
    || ProcessInfo.processInfo.thermalState == .critical
    || ProcessInfo.processInfo.isLowPowerModeEnabled
}
```
Checked at: start of `refreshMetadata`, mid-batch in task group, `performLibraryHeal` item loop, `markAllEpisodesAsWatched` season loop.

#### DataService (`@MainActor @Observable`)

**Role:** The `@MainActor` facade that sits between Views and `BackgroundDataService`. Debounces and batches refresh requests.

**Key methods:** `refreshMetadata(for:metadataOnly:force:)` coalesces requests into `pendingRefreshIDs` with 1.5s debounce timeout. `runMaintenance(modelContext:silent:)` dispatches `performLibraryHeal()` on background. `isProcessing(id:)` / `startProcessing(id:)` / `stopProcessing(id:)` track in-progress items to prevent duplicate user operations.

### 4.2 Query Engine

#### MediaFilterActor (`@ModelActor`)

**Role:** The query engine for the library. Handles filtering, sorting, grouping, and pagination.

**Singleton pattern:**
```swift
private let _filterActorCache = OSAllocatedUnfairLock<MediaFilterActor?>(uncheckedState: nil)
static func shared(modelContainer: ModelContainer) -> MediaFilterActor
```
Lock-bootstrapped singleton because `@ModelActor` init is async.

**Main entry point — `filterAndSort(...)`:**
1. Build `#Predicate<MediaItem>` via `MediaFilterPredicates.buildFilteredPredicate()`
2. Set `descriptor.propertiesToFetch = MediaItem.thumbnailProperties`
3. Apply sort order via `MediaSorting.applySortOrder(to:...)`
4. Determine if SQLite pagination is safe (no network/genre/year/badge filters, not stalled/quickBites/releaseRadar category, no smart rules)
5. Fetch (with or without `fetchLimit`/`fetchOffset`)
6. Run Swift-level `refineResults()` for: network (comma-parsed), language, genre (transformable), year, state, badge, search text, smart rules
7. Slice results for Swift-filtered pagination (up to 2000 items)
8. Build home category data if applicable (spotlight hero, continue watching, etc.)
9. Group results if grouping requested
10. Return `PaginatedResult`

**`refineResults()` pipeline:**
```
smartRules → quickBites (runtime filter) → stalled (date filter)
→ releaseRadar (badge+date filter) → badge match → network filter
(comma-split + lowercased + set membership)
→ language match → genre match (.contains) → year match
(Calendar.component) → state match → searchText match
(tokenized localizedStandardContains)
```

#### MediaFilterPredicates (static enum)

Builds `#Predicate<MediaItem>` per `NavigationCategory`. Each category has 4 variants: `{hasSearch, hasState}`. Covers: upcoming, inProgress, watchlist, loved, completed, archive, disliked, binge, movie/tvShow, catchUp, quickBites, stalled, smartUpcoming, releaseRadar, and default.

Badge and language are pushed to SQLite in `.completed`, `.movie`, `.tvShow`, and `default` categories. Network and genre are always Swift-level because they involve transformable arrays or comma-separated string parsing.

### 4.3 Caching Services

#### ImageCache (`@MainActor class`)

**Architecture:**
- **Memory:** `NSCache<NSString, CachedImageWrapper>` — adaptive sizing by RAM: 16GB+ → 256MB/1500 items, 8GB+ → 128MB/800, else 64MB/400
- **Disk:** File system directory with up to 500MB LRU eviction (trims to 80% when exceeded)
- **Index:** In-memory `diskCacheIndex: Set<String>` for O(1) disk presence checks, plus `urlToKeys: [String: Set<String>]` (thread-safe via `URLToKeysStore` with `OSAllocatedUnfairLock`) for reverse-lookup by original URL
- **Task Coalescing:** `activeTasks: [String: Task<Void, Never>]` keyed by `"url_widthxheight"` — concurrent requests for the same URL+size share a single task

**Main pipeline — `get(forKey:targetSize:priority:alwaysPreserveAlpha:)`:**
```
1. Memory check (exact key match) → return ImageContainer
2. Task coalescing (existing task for same key) → await, re-check memory
3. Cancel check → return nil
4. Create Task:
   a. Disk check via index + loadFromDisk (CGImageSourceCreateWithURL, memory-mapped)
   b. Store in memory, register urlToKeys, publish update → return
5. Cancel check → return nil
6. Download via URLSession
7. Save to disk (downsample + PNG/JPEG encode in background)
8. Decode from downloaded data (CGImageSourceCreateThumbnailAtIndex)
9. Store in memory, register urlToKeys, publish update
```

**Size-keyed caching:** Images cached at specific `targetSize` variants. `checkMemoryCache()` returns best available match — prefers exact size, falls back to larger-than-requested, then largest available (prevents black layouts).

**Memory pressure management:**
- `.warning`: shrink cache ceiling to 80MB/150 items
- `.critical`: shrink to 10MB/10 items, call `removeAllObjects()`, clear `urlToKeys`
- `NSCacheDelegate` synchronously removes evicted keys from `urlToKeys` via thread-safe store

**Disk pruning:** Every 50 saves, `pruneDiskCacheIfNeeded()` iterates all cached files sorted by modification date, evicts oldest until under 80% of 500MB limit.

#### SaveCoordinator (`@MainActor class`)

**Role:** Prevents thread locking and I/O bottlenecks from rapid successive saves.

`requestSave(_ context: ModelContext, delayMs: Int = 350)` — Cancels any pending save for this context, schedules a new one after `delayMs` via `Task.sleep`. Multiple rapid calls coalesce into one save.

`forceSave(_ context: ModelContext)` — Cancels pending debounced save, immediately calls `context.save()`.

### 4.4 Task Deduplication

#### SyncCoordinator (`actor`)

```swift
actor SyncCoordinator {
    private var inFlightTasks: [String: Task<Sendable, Error>] = [:]
    private var refCounts: [String: Int] = [:]
    
    func perform<T: Sendable>(key: String, operation: @Sendable () async throws -> T) async throws -> T
}
```

Key pattern: reference-counted task lifecycle. Each caller increments on join, decrements in `defer`. Task removed from dictionary only when last waiter finishes. Used by `BackgroundDataService.refreshSingleItem` with key `"sync_\(tmdbID)"` to prevent duplicate concurrent refreshes of the same item.

#### APIClient In-Flight Coalescing

The networking actor maintains dictionaries of in-flight tasks per resource key: `inFlightMovieDetails`, `inFlightTVDetails`, `inFlightSeasonDetails`. A second call for the same TMDB ID awaits the same task instead of firing duplicate network requests.

### 4.5 Badge Engine

**File:** `Services/BadgeEngine.swift`  
**Isolation:** Static methods on a struct. `nonisolated(unsafe)` mutable scan cache protected by `os_unfair_lock`.

**Badge pipeline (evaluated in priority order, first non-nil wins):**

| Stage | Badges | Trigger |
|---|---|---|
| 1. Milestone | PREMIERE | Episode 1 within -30..+3 days of air date |
| | FINALE | Last episode of season within -7..+14 days |
| | BINGE DROP | Multiple episodes aired same day within -14..+14 days |
| 2. Release Window | MOVIE PREMIERE | Movie within -3..+30 days of release date |
| | NEW | Within -14..0 days of release (past) |
| | SOON | Within 0..+2 days of release (future) |
| 3. Engagement | BINGE | 3+ episodes watched in last 48h, or 20%+ progress for liked/loved items |
| | BEHIND | Liked/loved item with next airing within 7 days |

**Scan cache:** `PersistentIdentifier`-keyed cache avoids re-scanning all episodes on every badge call. Invalidated via `invalidateScan(for:)` on episode state changes. Clear cache locked via `os_unfair_lock`.

### 4.6 Media State Broadcasting

#### MediaStateService (`@Observable @MainActor class`)

The centralized change-broadcasting service. Views observe these properties via `@Observable` tracking:

| Property | Type | Purpose |
|---|---|---|
| `needsFullRefreshCount` | `Int` | Incr on bulk changes. Views compare last-seen value. |
| `needsSingleItemUpdateCount` | `Int` | Incr on single item changes. |
| `refreshedItemID` | `String?` | ID of most recently refreshed item. |
| `lastChangedItemID` | `PersistentIdentifier?` | Persistent ID of most recently changed item. |

**Key methods:**
- `postMediaStateChanged(itemID:)` → incr `needsFullRefreshCount` or `needsSingleItemUpdateCount` + clear `TasteActor` cache
- `postItemRefreshed(id:persistentID:)` → set `refreshedItemID` + optional `lastChangedItemID` + clear taste cache
- `postBulkRefreshed()` → incr `needsFullRefreshCount` + clear taste cache

### 4.7 Background Work Orchestration

#### BackgroundTaskManager (`@MainActor class`)

**Entry:** `start(container:)` called from `App.swift`.
- Schedules `NSBackgroundActivityScheduler` (6-hour interval, `.background` QoS)
- Optionally runs `refreshStaleBadges()` on startup

**Idle handling:** `handleIdleStateChange(isIdle:)` called by `SleepManager` when app becomes idle → `performDripSync()` (refreshes up to 3 stale Active items)

**6-hour sync cycle:** `performBackgroundSync()`:
1. Refresh stale badges (items crossing time thresholds: upcoming→released, soon→new, new→recent)
2. Automated rolling backup via `LibraryImportExportService`
3. `DiscoverySyncService.syncLibrary()`
4. `BackgroundDataService.performLibraryHeal()`

**Drip sync:** `performDripSync()` — fetches items with `stateValue == "Active"` and `lastUpdated < 30 days ago`, refreshes up to 3.

### 4.8 Sleep Manager

**File:** `Services/SleepManager.swift`  
**Isolation:** `@Observable @MainActor class`

| State | Threshold | Effect |
|---|---|---|
| Idle | 60s inactivity | `isIdle = true`, triggers `BackgroundTaskManager.handleIdleStateChange` |
| Sleep | 120s inactivity | `isAsleep = true`, dims UI overlay, cancels polling timer, calls `purgeDataCache?()` |

**Interaction detection:** `NSEvent.addLocalMonitorForEvents(matching:)` for `.leftMouseDown`, `.rightMouseDown`, `.keyDown` on main window. Calls `resetTimer()` on event.

**Timer:** `Timer.publish(every: 5)` checks idle/sleep state every 5 seconds. Timer is cancelled on sleep entry, restarted on interaction resume.

**Environment injection:** `\.sleepManager` key plus `SleepOverlayModifier` via `.sleepModeSupport()` view modifier. `BackgroundDataService` and `BackgroundTaskManager` check `SleepManager.shared.isAsleep` before starting work.

### 4.9 Discovery Hub

#### DiscoverySyncService (`@ModelActor`)

**Role:** Maintains aggregated `NetworkEntity`, `GenreEntity`, `LanguageEntity`, `BadgeEntity` counts from library items.

**Full sync (`syncLibrary(force:)`):**
1. Fetch all existing entities, build lookup maps
2. Scan all `MediaItem` in 500-item batches
3. For each item: parse `cachedNetwork` (comma-split, trimmed) → resolve via `sourceToTarget` alias map → deduplicate per item → increment count
4. Count genres, languages, badges similarly
5. Delete entities with zero count
6. Extract network logo colors (`ColorExtractor`) for entities missing `themeColorHex`

**Incremental updates:**
- `updateItemAdded(_:)` — incr counts for the new item's networks/genres/language/badge
- `updateItemDeleted(network:genres:language:badge:)` — decr counts, delete entities at zero
- `onBadgeChanged(oldBadge:newBadge:)` — atomic badge count adjustment

**Studio alias system:** `StudioAliasEntity` maps source studio names to canonical targets (e.g., "HBO Max" → "HBO"). Sources are lowercased+trimmed for matching. `buildAliasMaps()` produces `sourceToTarget` and `targetToLogoSource` dictionaries.

### 4.10 Taste Engine

#### TasteActor (`@ModelActor`)

**Role:** Computes taste affinity profiles and generates "For You" recommendations.

**`calculateAffinityMaps()`:**
1. Fetch all items with `tasteValue != "None"` in 500-item batches
2. For each item, accumulate `CategoryStats` (loved/liked/disliked counts) per:
   - Genre (weight 15)
   - Creator (weight 20)
   - Cast member (weight 15)
   - Network (weight 5)
   - Language (weight 10)
3. Cache for 24 hours (static `@MainActor` cache)

**`calculateRecommendations()`:**
1. Fetch wishlist items (without recommendations, or force refresh)
2. Filter: must have release date, next airing date, or completed badge (BEHIND)
3. Score each item: `ratingScore * timeDecay`
   - `ratingScore = sum of (affinity × weight)` for matching genres/creators/cast/network/language
   - `timeDecay = 1 / (1 + 0.005 × daysDifference)` — symmetric, items airing soon score higher
4. Return top 10 with human-readable reasons (e.g., "From Christopher Nolan")

**Cache invalidation:** `clearCache()` called by `MediaStateService` on every library state change.

#### TasteMath (`static`)

```swift
struct CategoryStats {
    var loved: Int, liked: Int, disliked: Int, total: Int
    func affinity(cutoff: Int = 5) -> Double
}
```

`affinity(cutoff:)`: `(loved * 3 + liked * 1 + disliked * (-2)) / max(cutoff, total)`. Minimum `cutoff` items required for non-zero affinity.

### 4.11 Library Statistics

#### LibraryStatsActor (`@ModelActor`)

**Role:** Computes comprehensive `LibraryStats` for the Cinephile Lab analytics screen.

**Caching strategy (three tiers):**
1. In-memory: `cachedLightStats` + `cachedFullStats` on `@MainActor`, 1-hour TTL
2. Persistent disk: JSON files at `Application Support/LibraryStatsCache_full.json` and `_light.json`
3. Full recalculation

**Computed metrics:**
- Total counts: movies, TV shows, episodes, total runtime
- Genre DNA: top 10 genres by watch time
- Taste distribution: loved/liked/disliked/unrated counts
- Watch time history: per-day runtime, last 365 days (7-day average)
- Decade distribution: item count per release decade
- Barcode data: sequential genre visualization
- Top talent: top 5 actors + top 5 creators by taste rating, with profile images
- Taste affinities: genre/network/studio/cast/creator/language rankings

**Performance:**
- `propertiesToFetch` for minimal column reads
- Batch-fetches all watched episodes upfront (one query vs N traversals)
- Concurrent person image resolution (`withTaskGroup`, chunks of 5)

### 4.12 Networking

#### APIClient (`actor`)

**File:** `Services/Networking.swift` (606 lines)

**Three API providers:**

| Provider | Endpoints | Cache |
|---|---|---|
| TMDB | Search, movie/TV details, season episodes, person search | 7-day disk cache (1-day with `force`) |
| OMDB | Ratings, content ratings | 30-day disk cache |
| TVMaze | TV schedule lookup by TVDB ID, episode list | 24h disk cache |

**Disk cache:** Files stored at `Application Support/MediaTracker/api_details_cache/` with human-readable JSON filenames. Written via `FileIOActor` (max 6 concurrent I/O ops).

**In-memory search cache:** LRU dictionary with 20 entry limit, 5-minute TTL.

**Retry:** `executeWithRetry(maxAttempts: 5)` — exponential backoff with jitter. Retries on: rate limit (429), timeout, DNS failure, connection lost, 5xx server errors.

**Image URL construction:** `tmdbImageURL(path:size:) -> URL` with configurable size presets.

### 4.13 Calendar Computation

#### CalendarFilterActor (`@ModelActor`)

Computes `CalendarResult` for the Release Calendar view: aggregates items by release date, calculates intensity (count per day), and returns month-by-month data.

### 4.14 Supporting Services

| Service | Isolation | Role |
|---|---|---|
| `BackgroundActionService` | `@ModelActor` | Handles notification-triggered actions (mark-as-watched) |
| `FileIOActor` | `actor` | Serialized file I/O with max 6 concurrent ops and suspension-based backpressure |
| `NetworkThemeManager` | `@MainActor @Observable` | Maps network names to theme colors, cached in UserDefaults |
| `PrefetchManager` | `@MainActor` | Debounced image pre-fetching during scroll |
| `FeedbackManager` | `@MainActor` | Haptic + audio feedback for 8 gesture types |
| `MooreMetricsService` | `actor` | External recommendation API client |
| `SafeSave` | free function | Error-handled `context.save()` with logging |
| `AppLogger` | static enum | 8 categorized `Logger` instances (debug-only) |
| `AppErrorState` | `@MainActor @Observable` | Toast notification system with 4 severity levels |
| `ColorExtractor` | struct | Core Image histogram for dominant OKLCH colors |
| `GenreMapper` | struct | Decomposes compound genres, maps synonyms |
| `LanguageUtils` | struct | ISO code → display name with fast paths |
| `DateUtils` | struct | Date parsing with streaming service timezone rules |

---

## 5. View Layer

### 5.1 Navigation Architecture

The app uses a three-column `NavigationSplitView`:

```
NavigationSplitView
├── SidebarNavigation
│   ├── Main: Home, Discovery Hub, Release Calendar
│   ├── Library: All, Movies, TV Shows, In Progress, etc.
│   ├── Smart Hub: Binge, Catch Up, Stalled, Quick Bites, etc.
│   ├── Collections: user-created (manual + smart)
│   └── (settings gear icon)
├── CategoryRouterView (sidebar content)
│   └── Routes to:
│       ├── MainMediaGrid (for all, movies, tv shows, etc.)
│       ├── HomeViewSections (for home)
│       ├── DiscoveryHubView
│       ├── ReleaseCalendarView
│       ├── InsightsView
│       ├── FilteredLibraryGridView (discovery filters)
│       ├── SmartCollectionsHubView
│       ├── SearchView
│       └── SettingsView
└── DetailView (navigation destination from thumbnail tap)
    ├── MediaHeaderView (poster + title + metadata)
    ├── OverviewSection
    ├── CastSectionView
    ├── TVTrackingView (TV only — season cards + episode lists)
    ├── RecommendationSectionView
    └── DetailFloatingActionBar
```

**Keyboard shortcuts:**
- **Spacebar** (in detail view): TV → mark next episode watched; Movie → toggle completed
- **W** (in detail view): cycle status via `viewModel.cycleStatus()`
- Navigation shortcuts via standard SwiftUI keyboardShortcut

### 5.2 View Model Architecture

#### MediaViewModel (`@Observable @MainActor`)

Central state coordinator. Owns five sub-state objects:

| State Object | Key Properties | Purpose |
|---|---|---|
| `FilterState` | `selectedCategory`, `searchText`, `selectedNetworks`, `selectedLanguage`, `selectedGenre`, `selectedYear`, `selectedState`, per-category sort orders, group-bys | Current filter/sort configuration |
| `PaginationState` | `totalItemCount`, `currentOffset` (pageSize=50), `isLoadingMore`, `isFastScrolling` | Scroll pagination tracking |
| `CollectionState` | `selectedCollectionID`, `selectedCollectionName`, `showingNoteOverlay`, `currentCollectionNote` | Collection browsing state |
| `DisplayCache` | `displayedItems`, `recentlyAddedItems`, `homeContinueWatchingItems`, `spotlightHero`, `groupedItems`, `recommendations`, `featuredUpcomingItems`, `libraryTMDBIDs`, `isLibraryMetadataDirty`, `calendarCache` | All display data cached from actor queries |
| `DiscoveryCache` | `cachedNetworks`, `cachedGenres`, `cachedLanguages`, `cachedBadges`, `lastDiscoveryRefresh` | Discovery filter data |

**Mutation pattern:** All display cache updates are batched in a single `MainActor.run` block (7+ mutations in one synchronous scope, coalesced by SwiftUI into one layout pass).

#### DetailViewModel (`@Observable @MainActor`)

**Key properties:** `item: MediaItem?`, `isRefreshing`, `themeColor` + vibrant/contrast/warm/cool cached variants, `recommendations`, `isLoadingRecommendations`

**Theme color:** Computed from `item.themeColorHex` if available, or extracted from poster image via `ColorExtractor`. Cached as `vibrantThemeColor` (no opacity), `contrastThemeColor` (bright/dark), `warmThemeColor` (warm tone), `coolThemeColor` (cool tone).

**`needsUpdate` logic:** Returns `true` if `item.requiresMaintenanceRefresh` (lastUpdated > 30 days ago) or if TV show status is `"Returning Series"` and hasn't been refreshed in 1 day.

### 5.3 Key View Implementations

#### MediaThumbnailView (624 lines)

Universal poster card used in grid, hero, and search modes. Composes:
- `PosterView` (cached image + aurora glow)
- Progress ring (TV) or watched checkmark (Movie)
- `SmartBadgeView` (badge label + sparkle)
- Type badge (Movie/TV)
- `HoverMetadataPills` (title, year, next episode on hover)
- `HoverScaleEffect` (scale + shadow on hover)

Supports 3 size modes (grid, hero, search), contextual menu (state, taste, collection management), and matched geometry transitions for detail view navigation.

#### CachedImageView (144 lines)

```swift
struct CachedImage<Placeholder: View>: View {
    @State private var image: CGImage?
    @State private var broadcastCancellable: AnyCancellable?
    let url: URL?, targetSize: CGSize?, priority: ImagePriority
    var isFastScrolling: Bool = false
}
```

**Loading pipeline:**
1. `init`: Eagerly check `ImageCache.checkMemoryCache()` for exact size match → set `_image` initial state
2. `.task(id: url)`: If not fast-scrolling, call `attemptLoad()` → memory cache check → `loadImage()` → `ImageCache.shared.get(forKey:...)`
3. Suscribe to `ImageCache.shared.updates` via Combine for broadcast notifications
4. `onDisappear`: Cancel in-flight task via `ImageCache.shared.cancel(forKey:...)`
5. `isFastScrolling` toggle: Show `staticPlaceholder` while scrolling, load image when stopped

#### DetailView (507 lines)

Scroll view with pinned header, floating action bar, and matched sections. Sections appear with staggered animation. TV-specific: `TVTrackingView` with season cards and episode lists with watch toggles.

### 5.4 Reusable Components

| Component | Purpose |
|---|---|
| `GlassCard` | Material fill + stroke container card |
| `PillBadge` | Capsule badge with icon + text, filled/outlined |
| `HoverScaleEffect` | `ViewModifier` for hover scale + shadow |
| `ScrollingHStack` | Horizontal scroll with progress tracking |
| `SmartBadgeView` | Badge renderer with per-badge OKLCH colors |
| `DonutChart` | Rating distribution chart |
| `SectionHeader` | Section title with icon + subtitle |
| `InteractiveButtonStyle` | Button press scale + haptic feedback |

---

## 6. Key Workflows

### 6.1 Adding a New Item (Search → Import → Refresh)

```
User searches in SearchView
  → searchDebounced() fires Task
    → APIClient.searchMovies() / searchTVShows() [cached]
    → Also searches local library (lowercased title match)
  → User taps search result
    → DataService.createNewMediaItem(
         uniqueID: "movie_\(tmdbID)",
         tmdbID: tmdbID,
         type: .movie,
         title: title,
         overview: overview,
         posterURL: posterURL,
         releaseDateString: releaseDate
       )
    → BackgroundDataService.createNewMediaItem()
      → Uniqueness check via #Predicate on id
      → MediaItem.init() + insert
      → refreshMovie() / refreshTVShow() [calls APIClient]
        → Upsert MovieDetails/TVShowDetails + CastMember
        → extractAndSavePosterColor()
      → item.syncCachedProperties(force: true)
      → modelContext.save()
    → MediaStateService.postMediaStateChanged(itemID: uniqueID)
      → ViewModel catches change, calls filterAndSort() or fetchMetadataIfMatches()
      → DisplayCache updates
```

### 6.2 Episode Watch Propagation

```
User taps "Mark Watched" on TVEpisode
  → episode.markWatched(true)
    → isWatched = true, lastWatchedDate = now
    → season.watchedEpisodesCount += 1
    → tvShowDetails.watchedEpisodesCount += 1 (if season > 0)
    → item.cachedRuntime += ep.runtime
    → item.remainingEpisodesCount -= 1 (if aired)
    → BadgeEngine.invalidateScan(for: item.persistentModelID)
  → SaveCoordinator.requestSave(context, 350ms)
  → item.commitChange()
    → syncCachedProperties()
      → syncTVProperties() → calculateProgress()
      → BadgeEngine.calculateBadge()
      → storedIsUpcoming update
      → searchableText rebuild
    → MediaStateService.postMediaStateChanged(itemID: item.id)
  → ViewModel.updateList() updates DisplayCache arrays
  → SwiftUI re-renders
```

### 6.3 Full TV Show Metadata Refresh

```
DataService.refreshMetadata(for: [itemIDs], metadataOnly: false)
  → Debounce (1.5s)
  → BackgroundDataService.refreshMetadata(items, ...)
    → Check thermal state (early exit if throttled)
    → withTaskGroup(maxConcurrent: 8) {
        for id in items:
          refreshSingleItem(id:)
            → SyncCoordinator.perform(key: "sync_\(tmdbID)") {
                refreshTVShow(id:tmdbID:metadataOnly:force:)
                  → APIClient.fetchTVDetails(tmdbID)
                  → TVMaze lookup (if active)
                  → Upsert TVShowDetails
                  → Upsert CastMember (aggregate credits diff)
                  → Fetch seasons from TMDB: TaskGroup {
                      for seasonNumber in 1...numberOfSeasons:
                        APIClient.fetchSeasonDetails(tmdbID, seasonNumber)
                      }
                  → Create/update TVSeason + TVEpisode per season
                  → tvShowDetails.recalculateCachedProperties()
                  → item.syncCachedProperties(force: true)
                  → extractAndSavePosterColor(posterURL)
                }
              }
          }
      }
    → modelContext.save() [single batch save]
    → MediaStateService.postBulkRefreshed()
```

### 6.4 Badge Lifecycle

```
Every syncCachedProperties() call:
  → BadgeEngine.calculateBadge(for: item, now: Date)
    → Scan TV episodes (if TV and season/episode data loaded, use scan cache)
    → Pipeline:
      1. milestoneBadge:
         if episode.episodeNumber == 1 within -30..+3 days → PREMIERE
         if episode == last episode of season within -7..+14 days → FINALE
         if multiple episodes aired same day within -14..+14 days → BINGE DROP
      2. releaseWindowBadge:
         if movie within -3..+30 days of release → MOVIE PREMIERE
         if within -14..0 days of release → NEW
         if within 0..+2 days of release → SOON
      3. engagementBadge:
         if 3+ episodes watched in last 48h → BINGE
         if 20%+ progress for liked/loved item → BINGE (no sparkle)
         if liked item with next airing within 7 days → BEHIND
    → Returns first non-nil BadgeResult
  → Store in storedSmartBadgeLabel / storedSmartBadgeIsSparkle
  → If badge changed, notify DiscoverySyncService.onBadgeChanged()
```

### 6.5 Library Heal / Maintenance

```
DataService.runMaintenance()
  → BackgroundDataService.performLibraryHeal()
    → Check SleepManager.isAsleep (skip if sleeping)
    → Check 300s cooldown
    → repairOrphanedEntities()
       → TVSeason with no tvShowDetails → attach via showID map
       → TVEpisode with no season → attach via showID+seasonNumber map
    → purgeStaleSearchCache() (older than 7 days)
    → Fetch all items (thumbnailProperties)
    → For each item:
      → Check thermal state (break if throttled)
      → Check Task.isCancelled
      → Migrate legacy IDs (add "movie_"/"tv_" prefix)
      → If TV: recalculateCachedProperties(), auto-mark episodes if completed
      → Standardize seasons/episodes: set showID, uniqueID, airDateValue
      → tvShowDetails.recalculateCachedProperties(triggerSync: true, force: true)
      → item.syncCachedProperties(force: true)
    → modelContext.save()
    → NotificationManager.scheduleAllUpcomingNotifications()
    → DiscoverySyncService.syncLibrary(force: false)
```

### 6.6 Discovery Hub Sync

```
DiscoverySyncService.syncLibrary(force: false)
  → Check SleepManager.isAsleep (skip if sleeping)
  → Fetch AliasRules from StudioAliasEntity
  → Build sourceToTarget + targetToLogoSource maps
  → Scan all MediaItem in 500-item batches (propertiesToFetch: cachedNetwork, genres, language, badge)
  → For each item:
    → Split cachedNetwork by comma, trim, lowercase
    → Resolve via sourceToTarget alias map
    → Deduplicate per item (seenTargets set): count each target once
    → Accumulate to networkCounts[targetName]: (logo, count, priority, sources)
    → Increment genreCounts[genre] += 1
    → Increment languageCounts[language] += 1
    → Increment badgeCounts[badge] += 1
  → Update entities:
    → For each accumulated entity:
      → Fetch or create entity by name/code/label
      → Update count, sourceNames, logoPath, themeColorHex
    → Delete entities that have zero count
  → extractMissingColors() for networks without themeColorHex
    → Concurrent image download + ColorExtractor.topTwoColors()
```

### 6.7 Sleep/Idle Detection

```
Every 5 seconds (timer):
  → checkIdleState()
    → timeSinceInteraction >= 60s → isIdle = true → BackgroundTaskManager.handleIdleStateChange(true)
    → timeSinceInteraction >= 120s AND !preventSleep → enterSleepMode()
      → isAsleep = true (with animation)
      → timer.cancel() (stop polling)
      → purgeDataCache?() (clear heavy data)
    → timeSinceInteraction < 60s AND isIdle → isIdle = false

On user interaction (mouse/keydown on main window via NSEvent monitor):
  → resetTimer()
    → lastInteractionDate = now
    → isIdle = false
    → If isAsleep:
      → isAsleep = false (with animation)
      → startIdleTimer() (restart polling)
      → BackgroundTaskManager misses idle state (already reset)

Services check:
  BackgroundDataService: isAsleep check at start of heal, refresh
  BackgroundTaskManager: isAsleep check before drip sync
  DiscoverySyncService: isAsleep check at start of syncLibrary
  TasteActor: isAsleep check before affinity calculation
```

---

## 7. Design System

### 7.1 AppTheme Constants

All visual constants centralized in `AppTheme.swift`. Never hardcoded.

**Spacing:**
```swift
enum Spacing {
    static let micro: CGFloat = 4
    static let tiny: CGFloat = 6
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 24
    static let section: CGFloat = 32
    static let pageMargin: CGFloat = 20
}
```

**Radius:**
```swift
enum Radius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let card: CGFloat = 24
}
```

**Fonts:** 12 tiers from `tiny` (8pt) to `heroTitle` (60pt), plus `mono` variants and `badge` (10pt uppercase tracking).

**Shadows:** `card` (small y-offset, 6 blur), `elevated` (3 y-offset, 8 blur), `floating` (5 y-offset, 18 blur), `glow` (0 y-offset, 20 blur with color).

**Animations:**
```swift
enum Animation {
    static let springSnappy: Animation = .spring(duration: 0.3, bounce: 0.15)
    static let springGentle: Animation = .spring(duration: 0.5, bounce: 0.2)
    static let easeInOut: Animation = .easeInOut(duration: 0.3)
}
```

**Thumbnails:**
```swift
enum Thumbnail {
    static let tiny = CGSize(width: 80, height: 120)
    static let small = CGSize(width: 120, height: 180)
    static let medium = CGSize(width: 150, height: 225)
    static let large = CGSize(width: 200, height: 300)
}
```

### 7.2 Color System

**Global accent:** `AppTheme.Colors.accent` — reads dynamically from `AppThemeCoordinator.shared.accent`

**Backgrounds:** `AppTheme.Colors.background(for: colorScheme)` — delegated to coordinator. Supports 3 accent palettes: Standard (0), Earth Tones (1), Cool Tones (2).

**Card fills:** `AppTheme.Colors.cardFill(for: colorScheme)` — material-based with theme adaptation.

**Network theme colors:** Extracted from network logos via Core Image histogram. Stored in `NetworkEntity.themeColorHex`. Cached in `NetworkThemeManager` (UserDefaults).

**Smart badge colors:** Per-badge OKLCH colors in `SmartBadgeView`. E.g., BINGE → warm orange, PREMIERE → electric blue.

**OKLCH color space:** All theme colors use OKLCH for perceptual uniformity. `Color.init(oklchL: C, C: C, H: C, alpha: C)` custom initializer.

### 7.3 Keyboard Shortcuts

| Key | Context | Action |
|---|---|---|
| Spacebar | DetailView (TV) | `viewModel.markNextEpisodeWatched()` + haptic `.markWatched` |
| Spacebar | DetailView (Movie) | `viewModel.toggleWatched()` + haptic `.markWatched` / `.stateChange` |
| W | DetailView | `viewModel.cycleStatus()` + haptic response |

### 7.4 Haptic Feedback

`FeedbackManager.shared.trigger(.action)` with 8 patterns: `.click`, `.success`, `.warning`, `.stateChange`, `.markWatched`, `.taste`, `.addToLibrary`, `.removeFromLibrary`. Backed by `NSHapticFeedbackManager`.

---

## 8. Concurrency & Performance

### 8.1 Actor Usage Map

```
View Layer (SwiftUI, @MainActor implicitly)
  │
  ├── MediaViewModel (@MainActor @Observable)
  ├── DetailViewModel (@MainActor @Observable)
  │
  │   UI-thread safe: call DataService, never touch ModelContext
  │
  ├── DataService (@MainActor @Observable)
  │   facade: debounces, batches, dispatches to @ModelActor
  │
  │   Cross-actor boundary: DataService creates BackgroundDataService per call
  │
  ├── BackgroundDataService (@ModelActor)
  │   owns ModelContext, serialized writes, async network releases actor
  │
  ├── MediaFilterActor (@ModelActor)
  │   owns ModelContext, read-only queries, returns PaginatedResult
  │
  └── APIClient (actor)
      no SwiftData, protects mutable caches and in-flight registries
```

### 8.2 Save Patterns

| Pattern | When | Why |
|---|---|---|
| `SaveCoordinator.requestSave(context)` | Hot paths: episode toggles, state changes, taste changes | Debounces 350ms, prevents IO thrashing during rapid user actions |
| `SaveCoordinator.forceSave(context)` | Delete, clear database | Immediate persistence needed |
| `modelContext.save()` (direct) | Background operations (refresh, import, heal) | Single save at end of batch; no debounce needed outside UI |
| `safeSave(context)` | `@MainActor` contexts | Error-handled wrapper with logging |

### 8.3 Query Optimization

**`propertiesToFetch`:** All service-level fetches use `MediaItem.thumbnailProperties` (31 key paths) or `thumbnailPropertiesWithCast` (32 key paths) to avoid faulting heavy relationship objects (`movieDetails`, `tvShowDetails`, `storedCast`).

**SQLite-first filtering:** `MediaFilterPredicates.buildFilteredPredicate()` pushes category match, search text (`localizedStandardContains`), state, badge, and language to the `#Predicate` (SQLite). Only network (comma-split), genre (transformable), year (computed), and complex categories (stalled, quickBites, releaseRadar) fall to Swift-level refinement.

**Batch fetching:** Large library scans use 500-item batch fetches with `fetchLimit`/`fetchOffset`: DiscoverySyncService (all items), TasteActor (rated items), LibraryStatsActor.

**Denormalized counts:** `TVShowDetails.totalEpisodesCount` / `watchedEpisodesCount`, `TVSeason.watchedEpisodesCount`, `MediaItem.storedProgress` — avoid recalculating from episode-level data on every query.

### 8.4 Task Coalescing

| Service | Key Space | Mechanism |
|---|---|---|
| `SyncCoordinator` | String keys (`"sync_\(tmdbID)"`) | Actor with refcounted `[String: Task]` |
| `APIClient` (TMDB details) | Int tmdbID (`"movie_\(tmdbID)"`) | Actor with `[String: Task]` per endpoint |
| `ImageCache.get()` | `"url_widthxheight"` | `@MainActor` with `[String: Task]` |
| `DataService.refreshMetadata` | Item IDs in pending set | Debounce coalescing (1.5s window) |

### 8.5 Image Cache Architecture

```
Memory (NSCache, RAM adaptive)
  ├── Key: "\(url)_\(Int(width))x\(Int(height))"
  ├── Value: CachedImageWrapper (CGImage + metadata)
  ├── Cost: bytesPerRow * height
  ├── Count limit: 400–1500 (by RAM)
  └── Total cost limit: 64–256 MB (by RAM)

Disk (file system, max 500MB LRU)
  ├── Location: Application Support/CachedImages/
  ├── File: "\(hash)_\(Int(width))_\(Int(height))"
  ├── Format: PNG (if alpha) or JPEG @ 0.90 quality
  ├── Index: diskCacheIndex (Set<String>) for O(1) presence checks
  └── Pruning: LRU by contentModificationDate, evict oldest until ≤80% limit

Reverse Index (urlToKeys: URLToKeysStore)
  ├── O(1) lookup from original URL to all cached size variants
  ├── Thread-safe via OSAllocatedUnfairLock
  ├── Used for: fuzzy size matching, bulk eviction, cache invalidation
  └── Cleaned synchronously by NSCacheDelegate
```

### 8.6 Memory Pressure Response

| Level | Action |
|---|---|
| `.warning` | Shrink memory cache: 80MB/150 items |
| `.critical` | Shrink to 10MB/10 items, `removeAllObjects()`, clear `urlToKeys` |

NSCache also responds natively to system memory warnings via its internal eviction logic.

---

## 9. Critical Conventions

### 9.1 SwiftData

- **Always guard** `item.modelContext != nil` before any model operation
- Use `#Predicate` for type-safe queries. Enums stored as raw strings, use `MediaState.activeRaw`, `TasteValue.none.rawValue`, etc. in `#Predicate`
- Use `MediaItem.thumbnailProperties` for `propertiesToFetch` in all queries
- Use `item.commitChange()` for sync+save+broadcast (replaces 3-line boilerplate)
- Never call `context.save()` in hot paths — use `SaveCoordinator.requestSave()`
- **Live models:** Use `.liveModels` on arrays (filters out deleted/detached models):

```swift
extension Sequence where Element: AnyObject {
    var liveModels: [Element] { filter { $0.modelContext != nil } }
}
```

### 9.2 Animations

- Never call `dismiss()` inside `withAnimation` that changes view content
- Close overlays first, then dismiss after delay (`asyncAfter(deadline: .now() + 0.25)`)
- Defer `MediaStateService.postMediaStateChanged()` until after dismiss animation completes
- Use `AppTheme.Animation.springGentle` or `.springSnappy`
- For heavy statistical screens (CinephileLabView), use 350ms sleep to allow navigation slide animation before rendering final layout

### 9.3 Theming

- **Never hardcode** spacing, font sizes, or corner radii — use `AppTheme.*` constants
- Accent colors via `AppTheme.Colors.accent`, backgrounds via `.background(for:)`, card fills via `.cardFill(for:)`
- DetailView uses `.background(for:)` — integrates custom theme backgrounds with vibrant poster overlays
- `DiscoveryCard` uses network's own theme color, not the global accent
- Custom palettes (Accent, Earth Tones, Cool Tones) resolved and propagated via `AppThemeCoordinator`
- **Theme transition delay fix:** Subscribe to `NSApp.effectiveAppearance` in `App.swift`. When theme preference is Auto, compute concrete `systemColorScheme` rather than returning `nil`, forcing immediate SwiftUI redraw

### 9.4 Background Work

- Always check `SleepManager.shared.isAsleep` before starting work
- Always check thermal state (`ProcessInfo.processInfo.thermalState`) in loops
- Never perform heavy work on the `@MainActor` — dispatch to `@ModelActor`
- Batch saves: one `modelContext.save()` at the end of batch operations

### 9.5 Data Normalization

- `cachedNetwork` and `cachedNetworkLogoPath` are normalized at storage time via `normalizeCommaSeparated()`: trim whitespace per component, filter empty entries, join with `", "` separator
- Downstream consumers defensively trim when splitting (handles unnormalized data)

### 9.6 Error Handling

- Surface toasts via `AppErrorState.shared.surfaceError("message")`
- Log via `AppLogger.info()`, `.warning()`, `.debug()` (8 categorized loggers)
- Background tasks: wrap in `Task.detached`, catch errors, log + surface
- Use `safeSave(context)` for `@MainActor` saves (records file:line for debugging)

---

## 10. Testing

### 10.1 Test Suite Overview

172 tests across 19 files. Zero external dependencies — uses in-memory `ModelConfiguration`.

| Test File | Count | Focus |
|---|---|---|
| `FilterAndSortTests` | 16 | Predicate correctness, category filtering, sort orders, search, all filter dimensions, pagination |
| `PredicateTests` | 11 | `#Predicate` for each NavigationCategory variant (search × state × badge × language) |
| `BadgeEngineTests` | 21 | All 7 badge types, edge cases, exclusion rules, timing windows |
| `BingeLogicTests` | 10 | Milestone badges (BINGE DROP, FINALE, PREMIERE) with time-based scenarios |
| `StateTransitionTests` | 11 | Auto-complete, re-watching, drop, badge invalidation on state change |
| `ProgressCalculationTests` | 8 | Single/multi-season, partial watch, cached vs recalculated, remaining counts |
| `DetailViewModelTests` | 10 | `needsUpdate`, theme color fallback, toggleWatched, cycleStatus |
| `NetworkingTests` | 9 | Mock URL protocol, TMDB search/details, OMDB, rate limiting, image URL construction |
| `DiscoverySyncServiceTests` | 2 | Network deduplication, studio alias merging |
| `BackgroundDataServiceTests` | 5 | Item creation, duplicate detection, TV refresh, deletion |
| `SyncCachedPropertiesTests` | 6 | Badge recalculation, upcoming flag, searchable text |
| `MarkWatchedTests` | 4 | Episode marking, progress, runtime accumulation, double-watch idempotency |
| `MediaFilterActorTests` | 6 | Home category, continue watching, recently added, spotlight hero |
| `UtilityTests` | 4 | SyncCoordinator deduplication (now deterministic via XCTestExpectation) |
| Other | 49 | Model computed properties, GenreMapper, LanguageUtils, DateUtils, MediaCollection, media enums, TasteMath, persistence, MediaTracker entry |

### 10.2 In-Memory Container Pattern

All tests use the same model container setup pattern:

```swift
let schema = Schema([
    MediaItem.self, MovieDetails.self, TVShowDetails.self,
    TVSeason.self, TVEpisode.self, CastMember.self, MediaCollection.self,
    StudioAliasEntity.self, NetworkEntity.self, GenreEntity.self,
    LanguageEntity.self, BadgeEntity.self
])
let config = ModelConfiguration(isStoredInMemoryOnly: true)
let container = try! ModelContainer(for: schema, configurations: [config])
let context = container.mainContext
```

### 10.3 Mock Networking

`MockURLProtocol` intercepts all `URLSession` requests. Tests register mock responses per URL:

```swift
MockURLProtocol.requestHandler = { request in
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, ...)
    let data = mockJSONData(for: request.url!)
    return (response, data)
}
```

### 10.4 Test Patterns

- **State mutation → assert:** Create item, change state/taste, assert cached property updates
- **Mock network → call service → assert:** BackgroundDataService tests create items, mock TMDB responses via `MockURLProtocol`, then verify the correct `@Model` state
- **Concurrency → await:** All async tests use `await`/`async let`/`Task`/`XCTestExpectation` for deterministic timing
- **`@ModelActor` access:** Tests create actors with `modelContainer` parameter, call methods, await results

---

## Appendix A: Navigation Categories

| Category | Filter Logic |
|---|---|
| `.home` | Complex: spotlight (upcoming/binge), continue watching (Active, aired, unwatched), upcoming (badge-labeled) |
| `.upcoming` | `storedIsUpcoming == true` |
| `.inProgress` | `stateValue == "Active" && !storedIsUpcoming` |
| `.watchlist` | `stateValue == "Wishlist" && !storedIsUpcoming` |
| `.all` | No category filter |
| `.loved` | `tasteValue == "Love"` |
| `.completed` | `stateValue == "Completed"` |
| `.archive` | `stateValue == "On Hold" OR "Dropped" OR "Re-watching"` |
| `.disliked` | `tasteValue == "Dislike"` |
| `.binge` | `storedSmartBadgeLabel == "BINGE DROP" OR "BINGE"` |
| `.movie` | `typeValue == "Movie"` |
| `.tvShow` | `typeValue == "TV Show"` |
| `.catchUp` | `storedSmartBadgeLabel == "BEHIND"` |
| `.quickBites` | Runtime < 90min (movie) or < 25min (TV) |
| `.stalled` | On Hold/Dropped, or Active with no interaction in 90 days |
| `.smartUpcoming` | `storedSmartBadgeLabel == "PREMIERE"` |
| `.releaseRadar` | `storedSmartBadgeLabel != nil` with aired date ≤ now |

## Appendix B: SwiftData Model Counts

| Model | Unique | Cascade Delete |
|---|---|---|
| `MediaItem` | `id` | (root) |
| `MovieDetails` | — | via `MediaItem.movieDetails` |
| `TVShowDetails` | — | via `MediaItem.tvShowDetails` |
| `TVSeason` | `uniqueID` | via `TVShowDetails.seasons` |
| `TVEpisode` | `uniqueID` | via `TVSeason.episodes` |
| `CastMember` | `uniqueID` | via `MovieDetails.cast` + `TVShowDetails.cast` |
| `MediaCollection` | `id` | (root) |
| `NetworkEntity` | `name` | (root) |
| `GenreEntity` | `name` | (root) |
| `LanguageEntity` | `code` | (root) |
| `BadgeEntity` | `label` | (root) |
| `StudioAliasEntity` | `target` | (root) |
| `SearchCacheEntity` | `key` | (root) |
| `PersonImageEntity` | `name` | (root) |
