# MediaTracker — Technical Documentation

> **Version:** 6.0.0  •  **Bundle ID:** `com.vara.mediatracker`  •  **Minimum macOS:** 15.0

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Data Layer](#2-data-layer)
3. [Networking Layer](#3-networking-layer)
4. [Business Logic Services](#4-business-logic-services)
5. [UI Layer](#5-ui-layer)
6. [Concurrency Model](#6-concurrency-model)
7. [Performance Architecture](#7-performance-architecture)
8. [Build & Deployment](#8-build--deployment)
9. [Key Design Decisions](#9-key-design-decisions)

---

## 1. Architecture Overview

MediaTracker follows a **Service-Oriented MVVM** pattern with heavy use of Swift Actors for thread safety. The architecture is organized into four horizontal layers:

```
┌──────────────────────────────────────────────┐
│                 UI Layer                      │
│  SwiftUI Views + @Observable View Models     │
├──────────────────────────────────────────────┤
│           Business Logic Layer                │
│  Services (DataService, BadgeEngine, etc.)   │
│  Actors (MediaFilterActor, TasteActor, etc.) │
├──────────────────────────────────────────────┤
│            Data / Persistence Layer           │
│  SwiftData Models + ModelActor services      │
├──────────────────────────────────────────────┤
│            Networking Layer                   │
│  APIClient actor + Disk/Memory Cache         │
└──────────────────────────────────────────────┘
```

### Key Principles

- **Actor-isolated background processing:** All heavy computation (filtering, sorting, network calls) happens off the main actor via `@ModelActor` or standalone actors.
- **Observable state on MainActor:** UI-facing state is `@Observable` on `@MainActor` to integrate with SwiftUI's observation system.
- **Service singletons:** Core services (`DataService`, `MediaStateService`, `ImageCache`) are accessed via `.shared` singletons.
- **Denormalized cache properties:** `MediaItem` stores ~14 cached/denormalized properties (e.g. `cachedGenres`, `cachedNetwork`) to enable fast filtering without traversing relationships.

---

## 2. Data Layer

### 2.1 SwiftData Models

| Model | File | Purpose | Key Relationships |
|-------|------|---------|-------------------|
| `MediaItem` | `MediaItem.swift` | Core entity — a movie or TV show | `movieDetails` 1:1, `tvShowDetails` 1:1, `collections` N:M |
| `MovieDetails` | `MovieDetails.swift` | Movie-specific metadata | `item` inverse, `cast` 1:N |
| `TVShowDetails` | `TVShowDetails.swift` | TV show metadata + progress | `item` inverse, `seasons` 1:N, `cast` 1:N |
| `TVSeason` | `TVSeason.swift` | Season within a show | `tvShowDetails` inverse, `episodes` 1:N |
| `TVEpisode` | `TVEpisode.swift` | Episode within a season | `season` inverse |
| `CastMember` | `CastMember.swift` | Actor/crew attached to media | `movieDetails` or `tvShowDetails` |
| `MediaCollection` | `MediaCollection.swift` | User-created or smart collections | `items` N:M via `MediaItem.collections` |
| `NetworkEntity` | `EntityModels.swift` | TV network / streaming service | Standalone |
| `GenreEntity` | `EntityModels.swift` | Genre with usage count | Standalone |
| `LanguageEntity` | `EntityModels.swift` | Language code with count | Standalone |
| `BadgeEntity` | `EntityModels.swift` | Badge label with count | Standalone |
| `StudioAliasEntity` | `EntityModels.swift` | Studio name → canonical mapping | Standalone |
| `SearchCacheEntity` | `EntityModels.swift` | TMDB search result cache | Standalone |
| `PersonImageEntity` | `EntityModels.swift` | Person profile image URL cache | Standalone |
| `ImageCacheEntity` | `ImageCacheEntity.swift` | Disk-based image cache | Standalone |

### 2.2 Schema Migration

The schema is defined in `SchemaMigration.swift` using `SchemaV1` and the `MediaTrackerMigrationPlan`. Automatic migration is used for additive changes. If migration fails, a recovery mechanism deletes and recreates the store.

### 2.3 MediaItem — Denormalized Cache

`MediaItem` carries ~14 stored cached properties that mirror data from its related `MovieDetails`/`TVShowDetails` objects:

```
cachedGenres, cachedCreators, cachedLanguage, cachedNetwork,
cachedNetworkLogoPath, cachedNextAiringDate, cachedRuntime,
cachedEpisodeRuntime, cachedWatchedEpisodeCount, remainingEpisodesCount,
storedSmartBadgeLabel, storedSmartBadgeIsSparkle, storedIsUpcoming,
storedNextEpisodeLabel, storedWatchProgressLabel, storedProgress,
searchableText, storedCast
```

These are kept in sync via `syncCachedProperties()` (called from `MediaItem+Sync.swift`). The sync is triggered on state changes, after metadata refresh, and during library heal operations.

### 2.4 Identifier Scheme

Every `MediaItem` uses a composite ID string: `"{type}_{tmdbID}"` (e.g. `"movie_550"`, `"tv_1399"`). This provides uniqueness without requiring a separate database sequence. Episodes use `"{tmdbID}_{seasonNum}_{episodeNum}"`.

---

## 3. Networking Layer

### 3.1 APIClient Actor

**File:** `Networking.swift` (503 lines)

`APIClient` is a global actor singleton that manages all network communication with TMDB and TVMaze APIs.

**Key characteristics:**

- **Actor-isolated:** All mutable state (caches, in-flight task tracking) is protected by the actor.
- **Three-layer caching:** Each API endpoint family uses a specific caching strategy:
  1. **In-memory cache:** Short-lived (5 min TTL for search results).
  2. **Disk cache:** File-based JSON cache with 7-day TTL for detailed responses.
  3. **In-flight coalescing:** Concurrent requests for the same resource are deduplicated — the second caller awaits the first's task.
- **Retry with exponential backoff:** `executeWithRetry` retries rate-limited and timeout errors up to 5 times with exponential backoff.

**Endpoint families:**

| Method | API | Cache Strategy |
|--------|-----|----------------|
| `searchMovies` / `searchTVShows` | TMDB Search | In-memory (5 min) + Disk (7 day) |
| `fetchMovieDetails` | TMDB Movie | Disk (7 day) + In-flight coalescing |
| `fetchTVDetails` | TMDB TV | Disk (7 day) + In-flight coalescing |
| `fetchSeasonDetails` | TMDB Season | Disk (24h) + In-flight coalescing |
| `lookupTVMazeID` | TVMaze Lookup | No caching |
| `fetchTVMazeSchedule` | TVMaze Schedule | No caching |
| `fetchTVMazeEpisodes` | TVMaze Episodes | No caching |
| `searchPerson` | TMDB Person | No caching |

### 3.2 Image Cache

**File:** `ImageCache.swift` (744 lines)

`ImageCache` is a `@MainActor` singleton with a dual-tier caching system:

```
Request → Memory Cache (NSCache, 256MB / 1500 count)
            ↓ miss
         Disk Cache (SwiftData SQLite, 500MB cap)
            ↓ miss
         Network Download → save to memory + disk
```

**Key features:**
- **Retina-aware sizing:** Downsampling respects `screenScale` for crisp display on Retina displays.
- **Tiny proxy images:** A 50x75 thumbnail is saved alongside full-resolution images for placeholder use.
- **Memory pressure handling:** `performMemoryCompaction()` reduces cache limits under system memory pressure (warning → 80MB, critical → 10MB + full clear).
- **Disk cache pruning:** LRU eviction when total exceeds 500MB, trimming to 80% capacity.
- **URL→key reverse lookup:** `urlToKeys` tracks all size variants of a URL in memory for fuzzy matching.
- **Async disk index:** On launch, `diskCacheIndex` is loaded asynchronously from SQLite.

---

## 4. Business Logic Services

### 4.1 DataService (`@MainActor @Observable`)

**File:** `DataService.swift`

Orchestrates metadata refresh with batching and deduplication:
- Coalesces rapid refresh requests into a 1.5s batch window.
- Tracks session-level refreshed items to avoid redundant network calls.
- Coordinates `runMaintenance()`, `refreshAllBadges()`, and database clearing.

### 4.2 BackgroundDataService (`@ModelActor`)

**File:** `BackgroundDataService.swift` (730 lines)

The workhorse actor for all data operations:
- **Metadata refresh:** Fetches full TMDB details for movies/TV shows (including seasons, episodes, cast).
- **Item creation:** `createNewMediaItem()` creates a `MediaItem` from search results and immediately fetches full details.
- **Library heal:** `performLibraryHeal()` repairs orphaned entities, deduplicates, standardizes IDs, and recalculates cached properties.
- **Import/export:** `importLibraryData()` restores from JSON backup with episode progress preservation.
- **Episode completion:** `markAllEpisodesAsWatched()` handles auto-watch for completed TV shows.

**Thermal awareness:** All refresh operations check `isThermalThrottled` and skip under serious/critical thermal states or Low Power Mode.

### 4.3 MediaFilterActor (`@ModelActor`)

**File:** `MediaFilterActor.swift` (578 lines)

The core query engine for the library:
- **SQL+Swift hybrid filtering:** Pushes simple predicates to SQLite via `#Predicate`, runs complex filters (network, language, genre, year, state, badge, search text, smart rules) in-memory.
- **Paginated results:** Returns `PaginatedResult` with `displayed`, `featuredUpcoming`, `recentlyAdded`, `homeContinueWatching`, `spotlightHero`, `grouped`, and `totalCount`.
- **Home category processing:** Delegates to `processHomeCategory()` (in `MediaFilterHomeProcessor.swift`) for the curated home page with streaming highlights, transitions, active items, and recent wishlist items.
- **Smart collection support:** Applies smart rules when filtering for smart collections.
- **Single-item match:** `fetchMetadataIfMatches()` checks if a specific item matches current filters (used for in-place UI updates after state changes).

**Helper files:**
- `MediaFilterPredicates.swift` — Predicate builder functions.
- `MediaFilterSorter.swift` — Sort descriptor builder + in-memory sort utility.
- `MediaFilterGrouper.swift` — Grouping logic (by network, genre, year, decade).

### 4.4 BadgeEngine

**File:** `BadgeEngine.swift` (154 lines)

A static pipeline that calculates smart badges for media items:

```
calculateBadge(item, now)
  ├── milestoneBadge()  → PREMIERE, FINALE, BINGE DROP
  ├── releaseWindowBadge() → PREMIERE (movie), NEW, SOON
  └── engagementBadge() → BINGE, BEHIND, CATCH UP
```

The badge pipeline is prioritized: milestone badges take precedence over release window badges, which take precedence over engagement badges.

**Episode scan:** For TV shows, `scanEpisodes()` performs a single O(n) pass through all seasons/episodes collecting: next episode number, season episode count, next air date, same-day air count, and recently watched count.

### 4.5 TasteActor (`@ModelActor`)

**File:** `TasteActor.swift`

Recommendation engine that analyzes completed/liked items to find suggestions in the watchlist:
1. Builds affinity maps of preferred genres, networks, languages, creators, and actors.
2. Scores watchlist items against these preferences using weighted scoring.
3. Returns top recommendations with explanations.
4. Caches results for 24 hours.

### 4.6 MediaStateService (`@MainActor @Observable`)

**File:** `MediaStateService.swift` (38 lines)

A centralized observable broadcaster that replaces `NotificationCenter` for media state changes:
- `needsFullRefreshCount` — monotonically incrementing counter triggering full library refresh.
- `refreshedItemID` — specific item that was refreshed from the API.
- `lastChangedItemID` — specific item that was changed locally.

Views observe these properties via `.onChange(of:)` to react to data changes without `NotificationCenter`.

### 4.7 DiscoverySyncService (`@ModelActor`)

**File:** `DiscoverySyncService.swift`

Maintains a denormalized entity store (NetworkEntity, GenreEntity, LanguageEntity, BadgeEntity) for fast discovery hub queries. Batches library items in 500-item pages, extracts networks, genres, languages, and badges, and upserts them into the entity store.

### 4.8 SaveCoordinator (`@MainActor`)

**File:** `SaveCoordinator.swift`

Debounces SwiftData save requests (350ms by default) to prevent IO bottlenecks during rapid state changes (e.g., toggling multiple episodes watched). Supports `forceSave()` for immediate writes.

---

## 5. UI Layer

### 5.1 Navigation Hierarchy

```
ContentView
  └─ NavigationSplitView
       ├─ SidebarNavigation (categories, pinned collections, user collections)
       └─ LibraryDetailView
            └─ NavigationStack
                 └─ CategoryRouterView (routes by viewModel.selectedCategory)
                      ├─ SearchView (when isSearchActive)
                      ├─ DiscoveryHubView (.discover)
                      ├─ ReleaseCalendarView (.upcoming)
                      ├─ InsightsView (.insights)
                      ├─ SmartCollectionsHubView (.smartHub + no collection selected)
                      └─ MainLibraryView (all other categories)
```

### 5.2 Observation Model

The app uses SwiftUI's Observation framework (iOS 17+/macOS 14+):

```
@Observable classes:
  ├── MediaViewModel (24 properties) — central view state
  ├── DataService — refresh state, maintenance state
  ├── MediaStateService — refresh counters, change IDs
  └── AppThemeCoordinator — mood/dynamic color theme
```

**Critical observation paths:**

| Observer | Observed Property | Trigger |
|----------|------------------|---------|
| `ContentView.filterSubject.debounce(250ms)` | Manual `.send()` calls | Category change, filter change, search text, sidebar selection |
| `.task(id: viewModel.searchText)` | `searchText` | Keystroke → `filterSubject.send()` |
| `.onChange(of: needsFullRefreshCount)` | `MediaStateService.needsFullRefreshCount` | Any media state change |
| `.onChange(of: sidebarSelection)` | `sidebarSelection` | Sidebar navigation |

### 5.3 Key Views

| View | File | Purpose |
|------|------|---------|
| `ContentView` | `ContentView.swift` | Root split view, orchestrates data loading |
| `LibraryDetailView` | `ContentView.swift` | Navigation stack + toolbar + data coordination |
| `CategoryRouterView` | `CategoryRouterView.swift` | Routes to category-specific views |
| `MainLibraryView` | `MainLibraryView.swift` | Primary grid with hero carousel, continue watching, recently added |
| `MainMediaGrid` | `MainMediaGrid.swift` | Core media grid with FilteredLibraryGridView |
| `GroupedMediaGrid` | `GroupedMediaGrid.swift` | Grid with section headers |
| `DetailView` | `DetailView.swift` | Media detail with liquid glass, dynamic colors |
| `HomeHeroCard` | `HomeHeroCard.swift` | Spotlight card on home |
| `DiscoveryHubView` | `DiscoveryHubView.swift` | Network/genre/language exploration |
| `ReleaseCalendarView` | `ReleaseCalendarView.swift` | Calendar-based upcoming releases |
| `InsightsView` | `InsightsView.swift` | "Cinema DNA" analytics dashboard |
| `SearchView` | `SearchView.swift` | TMDB search + local results |
| `SettingsView` | `SettingsView.swift` | Preferences, API key, maintenance |
| `CachedImage` | `ImageCache.swift` | Async cached image with blur-up placeholders |

---

## 6. Concurrency Model

### 6.1 Actor Hierarchy

```
MainActor
  ├── DataService (Observable singleton)
  ├── MediaStateService (Observable singleton)
  ├── ImageCache (singleton)
  ├── SaveCoordinator (singleton)
  ├── AppErrorState
  ├── AppThemeCoordinator
  ├── BackgroundTaskManager
  ├── MemoryPressureMonitor
  └── MediaViewModel (Observable)

ModelActor (each has its own ModelContext)
  ├── MediaFilterActor
  ├── BackgroundDataService
  ├── TasteActor
  ├── DiscoverySyncService
  ├── CalendarFilterActor
  ├── LibraryStatsActor
  └── FileIOActor

actor (standalone)
  ├── APIClient (singleton)
  └── SyncCoordinator (singleton)
```

### 6.2 Data Flow Pattern

```
User Action (e.g., mark episode watched)
  │
  ▼
SwiftUI View (MainActor)
  │
  ▼
@Observable property change (MainActor)
  │
  ▼
.onChange(of:) / filterSubject.send()
  │
  ▼
Task.detached / BackgroundDataService (@ModelActor)
  │  └─ Network request via APIClient actor
  │  └─ SwiftData write via ModelContext
  │
  ▼
MediaStateService.postItemRefreshed() (MainActor)
  │
  ▼
ContentView.onChange(of: needsFullRefreshCount)
  │
  ▼
updateSingleItemInContentView() → MediaFilterActor.fetchMetadataIfMatches()
  │
  ▼
viewModel.displayedItems updated → SwiftUI re-render
```

### 6.3 ModelActor Pattern

`@ModelActor` macros create an actor with an isolated `modelContext`. Each actor has its own `ModelContext` connected to the shared `ModelContainer`. This provides:
- Thread-safe SwiftData access without locking.
- Isolated change sets that can be selectively saved or discarded.
- Automatic serialization of operations on the same actor.

**Important limitation:** Cross-actor model references are not directly possible. Results are passed as `PersistentIdentifier` or lightweight metadata structs (e.g., `MediaThumbnailMetadata`).

### 6.4 Task Management

- **Debounced filter updates:** `filterSubject.debounce(for: 250ms)` coalesces rapid filter changes.
- **Coalesced metadata refresh:** `DataService.refreshMetadata` batches IDs into a 1.5s window before starting refresh.
- **In-flight task coalescing:** `APIClient` deduplicates concurrent requests for the same resource.
- **SyncCoordinator:** An actor that prevents duplicate asynchronous tasks for the same resource key.

---

## 7. Performance Architecture

### 7.1 Optimizations Applied

| Category | Optimization | Location |
|----------|-------------|----------|
| **Memory** | NSCache (256MB/1500 count) for decoded images | ImageCache |
| **Memory** | SwiftData SQLite for disk image cache (500MB cap) | ImageCache |
| **Memory** | Memory pressure monitoring with automatic compaction | MemoryPressureMonitor |
| **Memory** | String interning via StringPool actor | StringPool |
| **Query** | Denormalized cached properties on MediaItem | MediaItem (23-41) |
| **Query** | SQL pushdown for simple predicates | MediaFilterPredicates |
| **Query** | In-flight task coalescing for duplicate network requests | APIClient (Networking.swift) |
| **Query** | Batch-fetched seasons/episodes (was N+1) | BackgroundDataService |
| **Query** | Pre-built dictionary for TVMaze O(1) lookups (was O(n*m)) | BackgroundDataService |
| **Query** | Session-level refresh deduplication | DataService |
| **UI** | Scroll-velocity-aware thumbnail quality | ScrollVelocityTracker |
| **UI** | Debounced filter updates (250ms) | ContentView |
| **UI** | Coalesced metadata refresh (1.5s window) | DataService |
| **UI** | Thumbnail metadata structs (lightweight, Sendable) | MediaThumbnailMetadata |
| **UI** | Synchronous cache snap in CachedImage initializer | CachedImage |
| **Network** | Disk cache with 7-day TTL for TMDB responses | APIClient |
| **Network** | In-flight task coalescing for all TMDB endpoints | APIClient |
| **Network** | Exponential backoff retry for rate limiting | APIClient |
| **Power** | Thermal state awareness (skip refresh when hot) | BackgroundDataService |
| **Power** | Low Power Mode detection | BackgroundDataService |
| **Concurrency** | @ModelActor for background DB operations | Multiple |
| **CPU** | Badge pipeline single-pass episode scan | BadgeEngine |

### 7.2 Background Task Management

**File:** `BackgroundTaskManager.swift`

The app schedules periodic background work:
- **Drip sync (60s timer):** Lightweight incremental library sync to keep discovery entities current.
- **Full sync:** Triggered on app launch and after significant library changes.
- **Badge refresh:** Stale badge recalculation every 5 minutes.
- **Library backup:** Automatic JSON export to Application Support.

All background tasks respect thermal state and idle/sleep conditions.

---

## 8. Build & Deployment

### 8.1 Build System

- **Swift Package Manager** (no Xcode project).
- **Swift 6.0** with strict concurrency checking.
- **macOS 15.0** deployment target.
- **Apple Silicon (arm64)** only.

### 8.2 Build Commands

```bash
# Development build
swift build

# Release build
swift build -c release --arch arm64

# Run tests
swift test

# Install to /Applications
bash install.sh
```

### 8.3 Project Structure

```
Sources/MediaTracker/
├── App.swift                    # @main entry point
├── ContentView.swift            # Root navigation + data coordination
├── DataService.swift            # Refresh orchestration
├── MediaViewModel.swift         # Central view state
├── MediaStateService.swift      # State broadcast
├── SaveCoordinator.swift        # Debounced saves
├── SyncCoordinator.swift        # Task deduplication
├── BackgroundDataService.swift  # Background TMDB ops
├── MediaFilterActor.swift       # Query engine
├── MediaFilterPredicates.swift  # Predicate builders
├── MediaFilterSorter.swift      # Sort logic
├── MediaFilterGrouper.swift     # Grouping logic
├── MediaFilterHomeProcessor.swift # Home page curation
├── BadgeEngine.swift            # Smart badge logic
├── TasteActor.swift             # Recommendations
├── DiscoverySyncService.swift   # Discovery entity sync
├── BackgroundTaskManager.swift  # Periodic background work
├── CalendarFilterActor.swift    # Calendar data
├── LibraryStatsActor.swift      # Library statistics
├── FileIOActor.swift            # File system operations
├── Networking.swift             # APIClient actor
├── ImageCache.swift             # Image caching system
├── ImageCacheEntity.swift       # Disk cache SwiftData model
├── MediaItem.swift              # Core SwiftData model
├── MediaItem+Sync.swift         # Cached property sync
├── MediaCollection.swift        # Collection model
├── MovieDetails.swift           # Movie metadata model
├── TVShowDetails.swift          # TV metadata + progress
├── TVSeason.swift               # Season model
├── TVEpisode.swift              # Episode model
├── CastMember.swift             # Cast model
├── EntityModels.swift           # Discovery + utility entities
├── MovieModels.swift            # TMDB movie API models
├── TVModels.swift               # TMDB TV API models
├── TMDBModels.swift             # Shared TMDB models
├── TVMazeModels.swift           # TVMaze API models
├── CommonModels.swift           # Shared structs/DTOs
├── SchemaMigration.swift        # Versioning + migration
├── StringPool.swift             # String interning
├── DateUtils.swift              # Date parsing helpers
├── LanguageUtils.swift          # Language name resolution
├── GenreMapper.swift            # Genre ID→name mapping
├── AppLogger.swift              # Unified logging
├── ColorExtractor.swift         # Poster color extraction
├── NetworkThemeManager.swift    # Brand color themes
├── AppThemeCoordinator.swift    # Dynamic mood colors
├── PrefetchManager.swift        # Image prefetching
├── ScrollVelocityTracker.swift  # Scroll speed detection
├── MemoryPressureMonitor.swift  # System memory monitoring
├── SleepManager.swift           # App idle/sleep state
├── NotificationManager.swift    # Local notifications
├── FeedbackManager.swift        # User feedback
├── LibraryImportExport.swift    # JSON backup/restore
├── UserDefaultsKeys.swift       # Centralized keys
├── AppTheme.swift               # Design system tokens
├── UIExtensions.swift           # SwiftUI extensions
├── ... (40+ view files)         # UI layer
└── Resources/                   # Resource bundle
```

### 8.4 CI/CD

**File:** `.github/workflows/release.yml`

- Triggered by `v*` tags.
- Builds ARM64 release, generates app icon, packages `.app` bundle.
- Creates DMG archive.
- Publishes GitHub Release with the DMG.

---

## 9. Key Design Decisions

### Why denormalized cache properties on MediaItem?

**Trade-off:** Write complexity for read speed. Filtering, sorting, and grouping are the most frequent operations. Reading from 14 stored properties on `MediaItem` is faster than traversing relationships to `MovieDetails`/`TVShowDetails` for every grid render. The cost is `syncCachedProperties()` which must be called on every data mutation.

### Why separate ModelActor per service?

Each `@ModelActor` (MediaFilterActor, BackgroundDataService, TasteActor, etc.) gets its own `ModelContext`. This allows concurrent read/write operations on different models without blocking, at the cost of cross-actor coordination via `PersistentIdentifier` and lightweight structs.

### Why Combine filterSubject instead of only Observation?

The 250ms debounce behavior requires Combine's `debounce(for:scheduler:)` operator. SwiftUI's Observation framework does not natively support time-based coalescing of change notifications. The `PassthroughSubject` is encapsulated within `MediaViewModel` and only exposed for coordination.

### Why TMDB + TVMaze dual API?

TMDB provides comprehensive metadata (cast, crew, genres, release dates). TVMaze provides higher-precision airstamps with timezone-aware scheduling. The TV show refresh pipeline first fetches TMDB data for structure, then overlays TVMaze airstamps for episode-level air date precision.

### Why three cast representations?

1. **TMDB API models** (`TMDBMovieCastMember`, `TMDBAggregateCastMember`) — decode JSON responses.
2. **SwiftData entities** (`CastMember`) — persistent storage with relationships.
3. **UI models** (`SimpleCastMember`) — lightweight Sendable structs for grid/filter display.

This separation avoids coupling the API schema to the persistence layer and the persistence layer to the UI.
