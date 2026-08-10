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
| `search_titles` | Search + filter (state/taste/mood/genre/network/language/type/upcoming) + sort (interaction, added, updated, release, nextAiring, title, loved) |
| `get_title_detail` | Full record for one title (genres, cast, providers, episode progress, collections) |
| `library_stats` | Totals by type/state/taste/mood, completion rate, watch time |
| `genre_dna` | Genres by affinity (`rank_by="affinity"`, top genre) or count (`rank_by="count"`, most-watched) |
| `network_studio_analysis` | Networks/studios by affinity or count, studio-alias grouped |
| `cast_rankings` | Cast by affinity/count, or directors/creators via `rank_by` |
| `watch_history` | Recently interacted titles (filterable by language/taste) |
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
