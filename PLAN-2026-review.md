# v9 "Arc" — 2026 in Review (plan)

Wrapped-style year recap **for 2026 only**, focused on content **released in 2026**
and watched by you — plus a watch-activity heatmap. Taste is derived **only** from
the set of 2026-released titles you watched, not your general library taste.

Scope: 2026. No data-model changes, no migrations. Read-only queries + new UI.

---

## Data inputs (all already stored)

| Signal | Source |
|---|---|
| Watched dates (TV) | `TVEpisode.watchedDate` (set by `markWatched`) |
| Movie completion date | `MediaItem.lastStateChangeDate` when `stateValue == "Completed"` |
| Release date | `MediaItem.releaseDate` (`Date?`, from TMDB) |
| Runtime | `MediaItem.cachedRuntime`, `TVEpisode.runtime` |
| Genre / network / cast | `cachedGenres`, `cachedNetwork`, `displayCast` |
| Year scope | `Calendar.current` window `2026-01-01..<2027-01-01` |

Notes:
- "Released in 2026" = `releaseDate` falls in the window. Nil/unknown dates are
  excluded and reported ("N titles have unknown release dates").
- TV "watched by me" = any `watchedDate` in 2026. Movie = completed in 2026.
- Heatmap covers **all** content watched in 2026 (not just 2026 releases).

---

## Phase 1 — Data service (`YearInReviewService`)

New `@ModelActor` (mirrors `ScopedStatsActor`), exposes a single
`compute(year: 2026) -> YearInReview` snapshot.

Queries (SQLite-first, `#Predicate` + `propertiesToFetch`):
1. TV episodes: `#Predicate { $0.isWatched && $0.watchedDate >= start && $0.watchedDate < end }`
   → aggregate per-day `(minutes, episodes)`. Also count distinct `showID`/item.
2. Movies: `#Predicate { $0.stateValue == "Completed" && $0.lastStateChangeDate >= start && ... }`
   → per-day completion + minutes.
3. 2026-released watched set: fetch items whose `releaseDate` is in-window **and**
   either (movie) completed / (TV) ≥1 watched episode in year → build a
   `[PersistentIdentifier]` set; reuse it for taste + grids.

Output model `YearInReview` (Sendable struct):
- `watchActivity: [MonthKey: DayActivity]` — 12-month bucket of per-day
  `(minutes, episodes, movies)` → powers the heatmap.
- `released2026: [MediaThumbnailMetadata]` split `movies` / `tvShows` (reuse
  `toMetadata` in `MediaFilterActor`).
- `taste`: `[GenreScore]`, `[NetworkScore]`, `[ActorScore]`, `[CreatorScore]`
  — genre/network/cast/creator affinity accumulated **only over released2026
  items**, scored with the existing `CategoryStats.affinity(cutoff:)` /
  `TasteMath` path used by `TasteActor`/`ScopedStatsActor`.
- `totals`: titles, episodes, minutes, longest streak, busiest day/month,
  day-level streak for the heatmap header.

Unit tests (`YearInReviewTests`): year-window scoping, release-2026 detection,
per-day aggregation, taste scoped-to-2026 (a 2025 classic must not contribute),
edge cases (nil dates, no data → empty state).

## Phase 2 — Heatmap view (`YearHeatmapView`)

GitHub-style **day-level heatmap** with month columns:
- 12 columns (Jan–Dec), one row per weekday, cell = a day of 2026.
- Cell intensity = minutes watched that day (0/4/8/12+ → 4 shade steps).
- Month labels above; tooltip per day ("Mon, Mar 3 — 2 episodes, 64 min").
- Uses `AppTheme.Colors` for the shade ramp (respect dark/light).
- Header stat row: total days watched, longest streak, most-watched month.
- "This year" (2026) fixed — no year selector in v1.

## Phase 3 — "Released in 2026, Watched by You"

Two sections in the review flow:
- **Movies**: poster grid (reuse `MediaThumbnailView` grid + `LazyVGrid`).
- **TV Shows**: same grid, with completion/airing badge.
- Each card links to its detail view (existing navigation).

## Phase 4 — Taste (scoped to 2026 releases only)

Cards that read from `released2026`-scoped affinity only:
- **Genre pills** (top 5 with scores).
- **Networks you binged in 2026** (top 3).
- **Actors/Creators of 2026** (top 5, reuse `HallOfFameView` row pattern).
- Copy explicitly labels this "from 2026 releases you watched".

## Phase 5 — Review flow + share card

- `YearInReviewView` entry point in `InsightsView` ("2026 in Review" card).
- Reveal: staged card-by-card with `AppTheme.Animation.springGentle`
  (reuse `StaggerModifier`). 350ms `Task.sleep` before content render to let the
  nav slide settle (AGENTS.md rule for heavy screens), with `.shimmering()`.
- **Share**: one compact summary card (title, totals, heat strip, top genre)
  via the existing `MediaShareCardView`/SharePreview plumbing. Export as image.

---

## Deliverables order

1. `YearInReview` model + `YearInReviewService` + tests (Phase 1)
2. `YearHeatmapView` (Phase 2)
3. 2026-releases grids (Phase 3)
4. Taste cards (Phase 4)
5. Flow, share, polish (Phase 5)

## Risks

- Sparse `watchedDate` on backfilled/imported libraries → heatmap undercounts;
  copy says "based on tracked watch history".
- TV shows released in 2026 that you watched partially: counted as "watched"
  (any episode). A "completed" badge distinguishes finished ones.
- `releaseDate` unknown for some titles → excluded from 2026 sections, surfaced
  in a footer note.
