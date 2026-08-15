# MediaTracker MCP Server

Read-only [MCP](https://modelcontextprotocol.io) server for the MediaTracker macOS app.
It opens the SwiftData store (`~/Library/Application Support/default.store`) and exposes
library search, filtering, sorting, and computed insights as MCP tools.

## Setup

```bash
cd Tools/MediaTrackerMCP
uv venv .venv
uv pip install --python .venv/bin/python -e .
```

> Note: Python's `plistlib` already decodes the `NSKeyedArchiver` plists used for
> genres/creators/watch-providers, and cast is plain JSON — no extra C libs needed.
> Uses the standalone `fastmcp` package (FastMCP 3.x).

## Smart collections

Smart (rule-based) collections are evaluated dynamically from their stored rules,
matching how the app computes them. For example `Thai GL` (rules: language `th` +
state `Completed`) is reported with its real 20 members even though its items
aren't stored as explicit joins.

## Register in opencode

Add to `~/.config/opencode/opencode.jsonc`:

```json
{
  "mcp": {
    "mediaTracker": {
      "type": "local",
      "enabled": true,
      "command": [
        "/Users/yourname/Projects/mediaTracker/Tools/MediaTrackerMCP/.venv/bin/python",
        "/Users/yourname/Projects/mediaTracker/Tools/MediaTrackerMCP/server.py"
      ]
    }
  }
}
```
> Note: `command` must be an array combining the interpreter + script — opencode's
> `McpLocalConfig` has no separate `args` field.

## Tools

| Tool | Description |
|---|---|
| `search_titles` | Search + filter (state/taste/mood/genre/network/language/type/upcoming, watched_from/watched_to on `lastStateChangeDate`) + sort (interaction, added, updated, release, nextAiring, title, loved) |
| `get_title_detail` | Full record for one title (genres, cast, providers, episode progress, collections) |
| `library_stats` | Totals by type/state/taste/mood, completion rate, watch time |
| `genre_dna` | Genres by affinity (`rank_by="affinity"`, top genre) or count (`rank_by="count"`, most-watched) |
| `network_studio_analysis` | Networks/studios by affinity or count, studio-alias grouped |
| `cast_rankings` | Cast by affinity/count, or directors/creators via `rank_by` |
| `watch_history` | Recently interacted titles (filterable by language/taste) |
| `monthly_watch_activity` | Movies (by `lastStateChangeDate`) and TV series (by per-episode `ZWATCHEDDATE`) watched per month of a year, local timezone |

Every item now includes `lastStateChangeDate` (when its state was last changed,
e.g. marked Completed/watched) alongside `dateAdded`, `lastInteraction`, and
`lastUpdated`. `search_titles` can filter on it with `watched_from` / `watched_to`
(half-open month interval, evaluated in the machine's local timezone to match the
app's `Calendar.current` grouping — important near month boundaries, e.g. a
timestamp `2026-04-30T18:30:00Z` is `2026-05-01` in IST). So
`watched_from="2026-05-01"` + `watched_to="2026-06-01"` returns titles whose state
changed (i.e. were watched) in May 2026.

For TV series, "when watched" is per-episode: `monthly_watch_activity(year)` counts
a show toward a month when >=1 of its episodes has a `ZWATCHEDDATE` that month
(evaluated in local time), alongside raw watched-episode totals and movies
completed that month.

> Core Data `Z_ENT` ids are **not hardcoded** for `ZTVEPISODE` — Core Data renumbers
> entities between model builds (seen at both 13 and 14). Episode queries skip the
> `Z_ENT` filter because that table only holds episode rows.
| `collections` | Manual + smart collections with counts |
| `upcoming_releases` | Upcoming titles sorted by date |
| `library_snapshot` | Compact whole-library JSON for context injection |

All ranking tools (`genre_dna`, `network_studio_analysis`, `cast_rankings`) accept
`rank_by="affinity"` (default, matches the app's Insights — affinity = taste-weighted
score) or `rank_by="count"` (most-watched by number of titles).

`cast_rankings` also accepts `rank_by="director"` (directors/creators by affinity)
and `rank_by="director_count"` (most-credited directors/creators). The result
includes a `scope` field (`"cast"` or `"director"`).

## Safety

The server opens the store **read-only** (`mode=ro`). For extra safety when testing,
snapshot the live store first:

```bash
Tools/MediaTrackerMCP/copy_store.sh /tmp/mt_snapshot.store
# then point schema.DEFAULT_STORE_PATH at the copy, or pass a path
```

## Insights parity

Stats/rankings are recomputed in SQL + Python and closely match the in-app
`LibraryStatsActor`, but are not byte-identical (the app uses weighted taste affinity).

## Test

```bash
cd Tools/MediaTrackerMCP && python3 -m pytest  # when tests are added
```
