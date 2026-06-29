# Episode Air Date: Data Sources, Resolution Logic & Hardcoded Times

This document details how episode air dates are sourced, resolved, and displayed
throughout the app — from API fetch to UI rendering.

---

## 1. API Data Sources

### TMDB (The Movie Database)

**Endpoint**: `GET /tv/{id}?append_to_response=external_ids,aggregate_credits,videos,watch/providers`

| Field | Source Path | Type | Notes |
|-------|------------|------|-------|
| Show overview | `overview` | String | |
| Poster | `poster_path` | String | Composed to full URL |
| Backdrop | `backdrop_path` | String | |
| First air date | `first_air_date` | String (`yyyy-MM-dd`) | Used for release year display |
| Network name | `networks[0].name` | String | e.g. "HBO", "Apple TV+" |
| Network logo | `networks[0].logo_path` | String | |
| Vote average | `vote_average` | Double | |
| Genres | `genres[].name` | [String] | |
| Status | `status` | String | "Running", "Ended", etc. |
| Original language | `original_language` | String | |
| IMDb ID | `external_ids.imdb_id` | String | |
| TVDB ID | `external_ids.tvdb_id` | Int | Used for TVMaze lookup |
| Trailer key | `videos.results` | String | Extracted via `extractTrailerKey()` |
| Streaming providers | `watch_providers.results` | [WatchProviderResult] | |
| Cast | `aggregate_credits.cast` | [CastMemberResult] | Top 15 by episode count |
| Creators | `created_by` | [CastMemberResult] | |
| Next episode date | `next_episode_to_air.air_date` | String (`yyyy-MM-dd`) | **Date only, no time** |
| Next episode number | `next_episode_to_air.episode_number` | Int | |
| Next season number | `next_episode_to_air.season_number` | Int | |

**Endpoint**: `GET /tv/{id}/season/{season}`

| Field | Source Path | Type | Notes |
|-------|------------|------|-------|
| Season air date | `air_date` | String (`yyyy-MM-dd`) | |
| Season name | `name` | String | |
| Episode count | `episode_count` | Int | |
| Episode name | `episodes[].name` | String | **Preferred over TVMaze** |
| Episode overview | `episodes[].overview` | String | |
| Episode air date | `episodes[].air_date` | String (`yyyy-MM-dd`) | **Date only, no time component** |
| Episode runtime | `episodes[].runtime` | Int (minutes) | **Trusted over TVMaze runtime** |

**Key limitation**: TMDB `air_date` is a date-only string (`"2026-07-01"`). It has no
time component, no timezone. TMDB sometimes provides incorrect dates (e.g., off-by-one
for streaming originals).

### TVMaze

**Endpoint**: `GET /shows/{id}?embed=nextepisode`

| Field | Source Path | Type | Notes |
|-------|------------|------|-------|
| Timezone | `network.country.timezone` or `webChannel.country.timezone` | String | e.g. "America/New_York" |
| Schedule time | `schedule.time` | String (`HH:mm`) | e.g. "21:00" for HBO |
| Schedule days | `schedule.days` | [String] | e.g. ["Wednesday"] |
| Genres | `genres` | [String] | |
| Show type | `type` | String | "Scripted", "Documentary", etc. |
| Next episode airdate | `_embedded.nextepisode.airdate` | String (`yyyy-MM-dd`) | |
| Next episode airstamp | `_embedded.nextepisode.airstamp` | String (ISO 8601) | e.g. `"2026-07-01T12:00:00+00:00"` |
| Next episode airtime | `_embedded.nextepisode.airtime` | String (`HH:mm`) | **Empty for streaming originals** |
| Next episode runtime | `_embedded.nextepisode.runtime` | Int | **Not trusted — inflated for K-dramas** |
| Network name | `network.name` or `webChannel.name` | String | e.g. "HBO", "Apple TV" |

**Endpoint**: `GET /shows/{id}/episodes`

| Field | Source Path | Type | Notes |
|-------|------------|------|-------|
| Season number | `season` | Int | |
| Episode number | `number` | Int | |
| Episode name | `name` | String | **Often generic** ("Chapter 1") — TMDB preferred |
| Airdate | `airdate` | String (`yyyy-MM-dd`) | **Accurate date** |
| Airstamp | `airstamp` | String (ISO 8601) | **Precise with timezone** (when real) |
| Airtime | `airtime` | String (`HH:mm`) | **Empty for streaming originals** |
| Runtime | `runtime` | Int | **Not trusted — inflated for K-dramas** |

**TVMaze `airstamp` precision patterns**:

| Show Type | `airtime` | `airstamp` | Meaning |
|-----------|-----------|------------|---------|
| Streaming original (Apple TV+, Netflix, etc.) | `""` (empty) | `T12:00:00+00:00` | **Placeholder** — noon UTC, not real |
| Network show (HBO, NBC, etc.) | `"21:00"` (real) | `T02:00:00+00:00` | **Real** — 9 PM ET = 2 AM UTC |

**Rule of thumb**: If `airtime` is empty, the `airstamp` is a noon-UTC placeholder.

---

## 2. Data Merge Strategy (Which Source Wins)

During `BackgroundDataService+Refresh.refreshTVShow()`, data from both APIs is merged:

| Field | Source | Rationale |
|-------|--------|-----------|
| **Episode air date (for display)** | TVMaze `airstamp` date > TVMaze `airdate` > TMDB `air_date` | TVMaze dates are more accurate for streaming originals |
| **Episode name** | TMDB | TVMaze often returns generic names ("Chapter 1") |
| **Episode overview** | TMDB | TVMaze summaries can be truncated |
| **Episode runtime** | TMDB | TVMaze runtime inflates K-dramas by 20-40 min |
| **Show-level next episode date** | TVMaze `airstamp` via `parseEpisodeDate()` | More precise than TMDB's date-only |
| **Timezone** | TVMaze `network.country.timezone` | |
| **Show schedule time** | TVMaze `schedule.time` | e.g. "21:00" for HBO |
| **Network name** | TVMaze `webChannel.name ?? network.name` | Used for streaming service rule matching |
| **Genres** | TVMaze (preferred) | More granular than TMDB genres |
| **Show type** | TVMaze `type` | "Scripted", "Documentary", etc. |
| **Streaming providers** | TMDB `watch_providers` | TVMaze doesn't have this |
| **Trailer key** | TMDB `videos` | TVMaze doesn't have this |
| **Cast** | TMDB `aggregate_credits` | TVMaze cast data is incomplete |
| **Poster/backdrop** | TMDB `poster_path` | Higher quality |
| **IMDb ID** | TMDB `external_ids` | |

---

## 3. Episode Date Resolution Pipeline

### Step 1: Date String Resolution

```
airstamp.date (TVMaze) → if nil → airDate (TMDB)
```

The date string (`resolvedDateString`) is resolved as:
1. If `airstamp` exists and is ≥10 chars → extract first 10 chars (the `yyyy-MM-dd`)
2. Otherwise → use `airDate` from TMDB

This ensures TVMaze's accurate date takes precedence over TMDB's sometimes-incorrect date.

### Step 2: `DateUtils.parseEpisodeDate()` Priority Chain

```
┌─────────────────────────────────────────────────────────────────────┐
│ 1. Streaming Service Rule (when airtime is empty)                  │
│    TVMaze date + hardcoded rule time + rule timezone               │
│    → Apple TV+ midnight ET, Netflix midnight PT, etc.              │
├─────────────────────────────────────────────────────────────────────┤
│ 2. Real TVMaze Airtime (network shows)                             │
│    TVMaze date + real airtime + show timezone                      │
│    → HBO 9 PM ET, NBC 8 PM ET, etc.                               │
├─────────────────────────────────────────────────────────────────────┤
│ 3. Real ISO Airstamp (skip noon-UTC placeholder)                   │
│    Full ISO timestamp parsed directly                              │
│    → Only fires when airstamp ≠ T12:00:00+00:00                   │
├─────────────────────────────────────────────────────────────────────┤
│ 4. Timezone + Time Fallback                                        │
│    Date + show timezone + schedule time (or 20:00 default)         │
├─────────────────────────────────────────────────────────────────────┤
│ 5. US 8 PM ET Fallback                                             │
│    Date + 20:00 America/New_York                                   │
└─────────────────────────────────────────────────────────────────────┘
```

**Inputs to `parseEpisodeDate()`**:

| Parameter | Source | Example |
|-----------|--------|---------|
| `dateString` | TMDB `ep.airDate` | `"2026-06-30"` |
| `time` | Always `nil` (not passed from episode creation) | `nil` |
| `airstamp` | TVMaze `mazeDict[key].airstamp` | `"2026-07-01T12:00:00+00:00"` |
| `timezone` | `tvDetails.timezone` (from TVMaze) | `"America/New_York"` |
| `serviceName` | `tvDetails.network` or `item.cachedNetwork` | `"Apple TV"` |
| `show` | `tvDetails` (TVShowDetails) | Full model |

**`hasRealAirtime` check**:
- `time?.isEmpty == false` — individual episode airtime (always `nil` from episode creation)
- `show?.nextEpisodeTime?.isEmpty == false` — show-level schedule time (from TVMaze `schedule.time`)

---

## 4. Streaming Service Hardcoded Rules

### `StreamingServiceRule` Configuration

| Service | Patterns | Release Time | Timezone | Day Offset | IST Equivalent |
|---------|----------|-------------|----------|------------|----------------|
| Apple TV+ | `["apple"]` | `00:00` | `America/New_York` | 0 | 9:30 AM (EDT) / 10:30 AM (EST) |
| Disney+ (Marvel/Star Wars) | `["star wars", "marvel"]` | `21:00` | `America/New_York` | 0 | 6:30 AM (EDT) / 7:30 AM (EST) |
| Disney+ (Standard) | `["disney"]` | `00:00` | `America/Los_Angeles` | 0 | 1:30 PM (PDT) / 2:30 PM (PST) |
| Netflix | `["netflix"]` | `00:00` | `America/Los_Angeles` | 0 | 1:30 PM (PDT) / 2:30 PM (PST) |
| Amazon/MGM+ | `["amazon", "prime", "mgm"]` | `00:00` | `America/Los_Angeles` | 0 | 1:30 PM (PDT) / 2:30 PM (PST) |
| Hulu/Peacock/Paramount+ | `["hulu", "peacock", "paramount"]` | `00:00` | `America/New_York` | 0 | 9:30 AM (EDT) / 10:30 AM (EST) |
| Max (Streaming) | `["max"]` | `00:00` | `America/Los_Angeles` | 0 | 1:30 PM (PDT) / 2:30 PM (PST) |
| HBO (Linear) | `["hbo"]` | `21:00` | `America/New_York` | 0 | 6:30 AM (EDT) / 7:30 AM (EST) |

**Matching logic**: `service.contains(pattern)` — case-insensitive. e.g. `"apple tv"` contains `"apple"`.

**When these rules fire**: Only when `hasRealAirtime` is `false` — i.e., TVMaze `airtime` is empty.
This is the case for **streaming originals** (Apple TV+, Netflix, Disney+, etc.) where TVMaze
doesn't know the exact air time and uses noon UTC as a placeholder.

**When these rules do NOT fire**: Network shows (HBO linear, NBC, CBS, etc.) where TVMaze has
a real `airtime` (e.g., "21:00"). Step 2 (real TVMaze airtime) handles these.

### Timezone Offsets (for IST reference)

| Timezone | DST | UTC Offset | Notes |
|----------|-----|-----------|-------|
| `America/New_York` | EDT (Mar-Nov) | UTC-4 | |
| `America/New_York` | EST (Nov-Mar) | UTC-5 | |
| `America/Los_Angeles` | PDT (Mar-Nov) | UTC-7 | |
| `America/Los_Angeles` | PST (Nov-Mar) | UTC-8 | |
| IST | N/A | UTC+5:30 | Indian Standard Time |

---

## 5. `TVEpisode` Date Caching

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `airDate` | `String?` | Raw date string from TMDB (`"2026-06-30"`) |
| `airstamp` | `String?` | Full ISO timestamp from TVMaze (`"2026-07-01T12:00:00+00:00"`) |
| `airDateValue` | `Date?` | **Persisted cache** — computed `Date` stored in SwiftData |

### Computed Property: `airDateAsDate`

```swift
var airDateValue: Date  // Checked first (persisted cache)
var airDateAsDate: Date? {
    airDateValue ?? DateUtils.parseEpisodeDate(airDate, airstamp: airstamp, ...)
}
```

The UI reads `airDateAsDate`. If `airDateValue` is already set (from a previous
calculation), it returns that cached value **without recalculating**.

### Auto-Recalculation via `didSet`

```swift
var airDate: String? {
    didSet { updateAirDateValue() }
}
var airstamp: String? {
    didSet { updateAirDateValue() }
}
```

When either `airDate` or `airstamp` changes, `updateAirDateValue()` recalculates
`airDateValue` using `DateUtils.parseEpisodeDate()`. The `isUpdatingAirDateValue`
flag prevents infinite recursion during the update.

### Update Flow in `refreshTVShow()`

```swift
// Existing episode update path:
episode.airDate = ep.airDate           // didSet → updateAirDateValue()
episode.airstamp = matchingMaze?.airstamp  // didSet → updateAirDateValue()
episode.runtime = ep.runtime
episode.updateAirDateValue()           // Explicit final recalculation
```

Three calls to `updateAirDateValue()` ensure the cached `airDateValue` is always
correct after a refresh.

---

## 6. Real-World Examples

### Example 1: Streaming Original — Maximum Pleasure Guaranteed (Apple TV+)

**Scenario**: Episode 8 "Hallidays"

| Source | Field | Value |
|--------|-------|-------|
| TMDB | `airDate` | `"2026-06-30"` (Tuesday — **incorrect**) |
| TVMaze | `airdate` | `"2026-07-01"` (Wednesday — **correct**) |
| TVMaze | `airstamp` | `"2026-07-01T12:00:00+00:00"` (noon UTC — **placeholder**) |
| TVMaze | `airtime` | `""` (empty) |
| TVMaze | `schedule.time` | `""` (empty) |
| TVMaze | `network` | `nil` (webChannel: "Apple TV") |

**Resolution**:
1. `resolvedDateString` = `"2026-07-01"` (from TVMaze airstamp, preferred over TMDB)
2. `hasRealAirtime` = `false` (both `time` and `nextEpisodeTime` are empty)
3. Service = `"apple tv"` → matches `StreamingServiceRule` pattern `"apple"`
4. Rule: `00:00` in `America/New_York` on `2026-07-01`
5. **Result**: Midnight EDT Wednesday = **9:30 AM IST Wednesday** ✓

### Example 2: Network Show — The Last of Us (HBO)

**Scenario**: Season 2 Episode 1 "Future Days"

| Source | Field | Value |
|--------|-------|-------|
| TMDB | `airDate` | `"2025-04-13"` |
| TVMaze | `airdate` | `"2025-04-13"` |
| TVMaze | `airstamp` | `"2025-04-14T01:00:00+00:00"` (1 AM UTC = 9 PM ET) |
| TVMaze | `airtime` | `"21:00"` (**real time**) |
| TVMaze | `schedule.time` | `"21:00"` |
| TVMaze | `network.name` | `"HBO"` |
| TVMaze | `timezone` | `"America/New_York"` |

**Resolution**:
1. `resolvedDateString` = `"2025-04-13"` (from TVMaze airstamp)
2. `hasRealAirtime` = `true` (`nextEpisodeTime` = `"21:00"`)
3. Step 2 fires: TVMaze date `"2025-04-13"` + airtime `"21:00"` + timezone `"America/New_York"`
4. **Result**: 9 PM EDT Sunday April 13 = **7:30 AM IST Monday April 14** ✓

### Example 3: Streaming Original — Severance (Apple TV+)

| Source | Field | Value |
|--------|-------|-------|
| TMDB | `airDate` | `"2025-01-17"` |
| TVMaze | `airdate` | `"2025-01-17"` |
| TVMaze | `airstamp` | `"2025-01-17T12:00:00+00:00"` (noon UTC — **placeholder**) |
| TVMaze | `airtime` | `""` (empty) |
| TVMaze | `network` | `nil` (webChannel: "Apple TV") |

**Resolution**: Same as Example 1 — Apple TV+ rule fires → midnight ET on Jan 17.

---

## 7. Edge Cases & Known Limitations

### Noon-UTC Placeholder Detection

TVMaze uses `T12:00:00+00:00` as a placeholder when it doesn't know the real air time.
This is detected and skipped in step 3 of the resolution chain:

```swift
if let airstamp = airstamp, !airstamp.contains("T12:00:00+00:00"), ...
```

### TMDB Date Inaccuracy

TMDB sometimes provides incorrect `air_date` values (e.g., off-by-one for streaming
originals). The fix: `resolvedDateString` always prefers the TVMaze airstamp date
when available, falling back to TMDB only when no airstamp exists.

### `airDateValue` Persistence

The cached `airDateValue` is persisted to SwiftData. If the resolution logic changes
(e.g., after a code update), existing episodes retain their old cached date until
the next refresh triggers `updateAirDateValue()`.

### Network Name Resolution for Streaming Rules

The `serviceName` for rule matching comes from:
1. `tvDetails.network` — set from TVMaze `webChannel.name ?? network.name`
2. `item.cachedNetwork` — fallback from `syncCachedProperties()`

For streaming originals, `tvDetails.network` is the webChannel name (e.g., "Apple TV").
For network shows, it's the network name (e.g., "HBO").

### `nextEpisodeTime` on `TVShowDetails`

This is the show-level schedule time from TVMaze `schedule.time` (e.g., "21:00" for HBO).
For streaming originals, this is empty `""`. It's used as a fallback in steps 2 and 4
of the resolution chain.

---

## 8. File Reference

| File | Purpose |
|------|---------|
| `Sources/MediaTracker/Services/DateUtils.swift` | `parseEpisodeDate()` — core resolution logic, `StreamingServiceRule` definitions |
| `Sources/MediaTracker/Models/TVEpisode.swift` | `airDateAsDate`, `updateAirDateValue()`, `airDateValue` cache |
| `Sources/MediaTracker/Models/TVMazeModels.swift` | `TVMazeEpisode` struct with `airdate`, `airstamp`, `airtime` |
| `Sources/MediaTracker/Models/TVShowDetails.swift` | `timezone`, `nextEpisodeTime`, `network` |
| `Sources/MediaTracker/Services/BackgroundDataService+Refresh.swift` | `refreshTVShow()` — fetches both APIs, merges data, creates/updates episodes |
| `Sources/MediaTracker/Services/Networking.swift` | `fetchTVMazeSchedule()`, `fetchTVMazeEpisodes()`, `fetchSeasonDetails()` |
| `Sources/MediaTracker/Views/TVTrackingView.swift` | UI: `episode.airDateAsDate?.formatted(...)` for date display |
