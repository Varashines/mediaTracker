"""MediaTracker MCP server.

Read-only access to the MediaTracker SwiftData store. Exposes search, detail,
and computed insights tools over the MCP stdio transport.
"""

import os
import sys
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastmcp import FastMCP
from schema import (
    open_store, to_date, local_date, local_month_key,
    decode_plist_array, decode_json_list, StoreError,
)
mcp = FastMCP("media-tracker")

# Core Data Z_ENT values (entity -> int). MediaItem is 6.
# NOTE: do not hardcode TVEpisode's Z_ENT — Core Data renumbers entities between
# model builds (episodes have been seen at both 13 and 14). Episode queries
# deliberately skip the Z_ENT filter since ZTVEPISODE only holds episode rows.
MEDIA_ITEM_ENT = 6
MEDIA_COLLECTION_ENT = 5

VALID_STATES = {"Wishlist", "Active", "Completed", "On Hold", "Dropped", "Rewatching"}
VALID_TASTES = {"Love", "Like", "Dislike", "None"}
VALID_MOODS = {"Cozy", "Intense", "Trippy", "Epic", "Sad", "Chill"}
VALID_TYPES = {"Movie", "TV Show"}
VALID_SORTS = {
    "interaction", "added", "updated", "release",
    "nextAiring", "title", "loved", "watched",
}


def _decode_smart_rules(blob) -> list[dict]:
    """Decode the smart-rules JSON. Swift Codable encodes enum cases as
    {'caseName': {'_0': value}} (e.g. {'language': {'_0': 'th'}})."""
    if not blob:
        return []
    try:
        data = json.loads(blob.decode("utf-8"))
    except Exception:
        return []
    return data if isinstance(data, list) else []


def _matches_rules(row, rules: list[dict]) -> bool:
    """Evaluate smart rules against a raw ZMEDIAITEM row (all must match)."""
    import datetime
    for rule in rules:
        if not isinstance(rule, dict):
            return False
        for case, payload in rule.items():
            if not isinstance(payload, dict):
                return False
            value = payload.get("_0")
            if case == "genre":
                if value not in {g.lower() for g in decode_plist_array(row["ZCACHEDGENRES"])}:
                    return False
            elif case == "language":
                if (row["ZCACHEDLANGUAGE"] or "").lower() != (value or "").lower():
                    return False
            elif case == "state":
                if row["ZSTATEVALUE"] != value:
                    return False
            elif case == "taste":
                if row["ZTASTEVALUE"] != value:
                    return False
            elif case == "mediaType":
                if row["ZTYPEVALUE"] != value:
                    return False
            elif case == "badge":
                if row["ZSTOREDSMARTBADGELABEL"] != value:
                    return False
            elif case == "network":
                raw = (row["ZCACHEDNETWORK"] or "")
                nets = {n.strip().lower() for n in raw.split(",") if n.strip()}
                if (value or "").lower() not in nets:
                    return False
            elif case == "releaseYear":
                # {'releaseYear': {'_0': [year, 'is'|'after'|'before']}}
                year, comp = value[0], value[1]
                release = row["ZRELEASEDATE"]
                if not release:
                    return False
                item_year = datetime.datetime.fromtimestamp(
                    release + 978307200.0).year
                if comp == "is" and item_year != year:
                    return False
                if comp == "after" and item_year <= year:
                    return False
                if comp == "before" and item_year >= year:
                    return False
            elif case == "releaseYearRange":
                start, end = value[0], value[1]
                release = row["ZRELEASEDATE"]
                if not release:
                    return False
                item_year = datetime.datetime.fromtimestamp(
                    release + 978307200.0).year
                if not (start <= item_year <= end):
                    return False
            else:
                return False
    return True


def _collection_member_ids(conn, collection_pk: int, is_smart: bool, rules: list[dict]) -> set[int]:
    """Return the Z_PK set of items in a collection. Smart collections are
    computed dynamically from their rules (like the app does); manual
    collections use the stored join table."""
    if not is_smart:
        rows = conn.execute(
            "SELECT Z_6ITEMS FROM Z_5ITEMS WHERE Z_5COLLECTIONS = ?",
            (collection_pk,),
        ).fetchall()
        return {r[0] for r in rows}
    # Smart: evaluate rules over all non-soft-deleted items.
    rows = conn.execute(
        "SELECT * FROM ZMEDIAITEM WHERE Z_ENT = ? AND ZISSOFTDELETED = 0",
        (MEDIA_ITEM_ENT,),
    ).fetchall()
    return {r["Z_PK"] for r in rows if _matches_rules(r, rules)}


def _row_to_item(row) -> dict:
    """Convert a ZMEDIAITEM row into a friendly dict."""
    return {
        "id": row["ZID"],
        "title": row["ZTITLE"],
        "type": row["ZTYPEVALUE"],
        "state": row["ZSTATEVALUE"],
        "taste": row["ZTASTEVALUE"],
        "mood": row["ZMOOD"],
        "overview": row["ZOVERVIEW"],
        "language": row["ZCACHEDLANGUAGE"],
        "network": row["ZCACHEDNETWORK"],
        "genres": decode_plist_array(row["ZCACHEDGENRES"]),
        "creators": decode_plist_array(row["ZCACHEDCREATORS"]),
        "watchProviders": decode_plist_array(row["ZCACHEDWATCHPROVIDERS"]),
        "cast": [c.get("name") for c in decode_json_list(row["ZSTOREDCAST"]) if c.get("name")],
        "runtimeMinutes": row["ZCACHEDRUNTIME"],
        "isUpcoming": bool(row["ZSTOREDISUPCOMING"]),
        "badge": row["ZSTOREDSMARTBADGELABEL"],
        "progress": row["ZSTOREDPROGRESS"],
        "releaseDate": to_date(row["ZRELEASEDATE"]),
        "nextAiringDate": to_date(row["ZCACHEDNEXTAIRINGDATE"]),
        "dateAdded": to_date(row["ZDATEADDED"]),
        "lastInteraction": to_date(row["ZLASTINTERACTIONDATE"]),
        "lastStateChangeDate": to_date(row["ZLASTSTATECHANGEDATE"]),
        "lastUpdated": to_date(row["ZLASTUPDATED"]),
    }


def _conn():
    return open_store()


def _sort_key(item: dict, sort_by: str):
    col = {
        "interaction": "ZLASTINTERACTIONDATE",
        "added": "ZDATEADDED",
        "updated": "ZLASTUPDATED",
        "release": "ZRELEASEDATE",
        "nextAiring": "ZCACHEDNEXTAIRINGDATE",
        "title": "ZTITLE",
        "watched": "ZLASTSTATECHANGEDATE",
    }.get(sort_by)
    if sort_by == "loved":
        return -1  # handled separately
    return col


# ---------------------------------------------------------------- search ---

@mcp.tool()
def search_titles(
    query: str = "",
    state: str = "",
    taste: str = "",
    mood: str = "",
    genre: str = "",
    network: str = "",
    language: str = "",
    type: str = "",
    is_upcoming: bool = False,
    watched_from: str = "",
    watched_to: str = "",
    sort_by: str = "interaction",
    order: str = "desc",
    limit: int = 50,
) -> dict:
    """Search titles in the library with combinable filters and sorting.

    Filters: query (title contains), state, taste, mood, genre, network,
    language (code like 'en'/'hi'/'te'), type ('Movie'/'TV Show'), is_upcoming.
    Date filters on lastStateChangeDate (half-open month interval, evaluated in
    the machine's local timezone to match the app's Calendar.current grouping):
    watched_from (inclusive, e.g. '2026-05-01') and watched_to (exclusive,
    e.g. '2026-06-01'). E.g. watched in May 2026 = watched_from='2026-05-01'
    watched_to='2026-06-01'.
    Sort by: interaction, added, updated, release, nextAiring, title, loved, watched.
    order: 'asc' or 'desc'.
    """
    if sort_by not in VALID_SORTS:
        return {"error": f"sort_by must be one of {sorted(VALID_SORTS)}"}
    if state and state not in VALID_STATES:
        return {"error": f"state must be one of {sorted(VALID_STATES)}"}
    if taste and taste not in VALID_TASTES:
        return {"error": f"taste must be one of {sorted(VALID_TASTES)}"}
    if mood and mood not in VALID_MOODS:
        return {"error": f"mood must be one of {sorted(VALID_MOODS)}"}
    if type and type not in VALID_TYPES:
        return {"error": f"type must be one of {sorted(VALID_TYPES)}"}

    q = "SELECT * FROM ZMEDIAITEM WHERE Z_ENT = ?"
    params: list = [MEDIA_ITEM_ENT]
    if query:
        q += " AND ZTITLE LIKE ?"
        params.append(f"%{query}%")
    if state:
        q += " AND ZSTATEVALUE = ?"
        params.append(state)
    if taste:
        q += " AND ZTASTEVALUE = ?"
        params.append(taste)
    if type:
        q += " AND ZTYPEVALUE = ?"
        params.append(type)
    if is_upcoming:
        q += " AND ZSTOREDISUPCOMING = 1"

    conn = _conn()
    rows = conn.execute(q, params).fetchall()
    items = [_row_to_item(r) for r in rows]

    # Post-filter transformable fields (not SQL-safe).
    if language:
        items = [i for i in items if (i["language"] or "").lower() == language.lower()]
    if genre:
        items = [i for i in items if genre.lower() in {g.lower() for g in i["genres"]}]
    if network:
        items = [i for i in items if network.lower() in (i["network"] or "").lower()]
    if watched_from:
        items = [i for i in items if (d := local_date(i["lastStateChangeDate"])) and d >= watched_from]
    if watched_to:
        items = [i for i in items if (d := local_date(i["lastStateChangeDate"])) and d < watched_to]

    if sort_by == "loved":
        items = [i for i in items if i["taste"] == "Love"]
        items.sort(key=lambda i: i["lastInteraction"] or "", reverse=(order == "desc"))
    else:
        col = _sort_key(items[0], sort_by) if items else "ZLASTINTERACTIONDATE"
        # Re-run sort in SQL-free way: we already have rows; use the dict field.
        field = {
            "interaction": "lastInteraction", "added": "dateAdded",
            "updated": "lastUpdated", "release": "releaseDate",
            "nextAiring": "nextAiringDate", "title": "title",
            "watched": "lastStateChangeDate",
        }.get(sort_by, "lastInteraction")
        items.sort(key=lambda i: i[field] or "", reverse=(order == "desc"))

    return {"count": len(items), "items": items[:limit]}


# --------------------------------------------------------------- detail ---

@mcp.tool()
def get_title_detail(id: str) -> dict:
    """Return the full record for a single title by its unique id (e.g. 'movie_123', 'tv_456')."""
    conn = _conn()
    row = conn.execute(
        "SELECT * FROM ZMEDIAITEM WHERE Z_ENT = ? AND ZID = ?", (MEDIA_ITEM_ENT, id)
    ).fetchone()
    if not row:
        return {"error": f"No title with id '{id}'"}

    item = _row_to_item(row)
    item["castDetail"] = decode_json_list(row["ZSTOREDCAST"])

    # Watch progress: count watched/total episodes.
    # Note: no Z_ENT filter here — ZTVEPISODE only contains TVEpisode rows, and
    # hardcoding an entity id (e.g. 13) breaks when Core Data renumbers Z_ENT.
    if item["type"] == "TV Show":
        show_pk = int(id.split("_")[-1]) if "_" in id else 0
        ep_count = conn.execute(
            "SELECT COUNT(*) FROM ZTVEPISODE WHERE ZSHOWID = ?",
            (show_pk,),
        ).fetchone()[0]
        watched = conn.execute(
            "SELECT COUNT(*) FROM ZTVEPISODE WHERE ZSHOWID = ? AND ZISWATCHED = 1",
            (show_pk,),
        ).fetchone()[0]
        item["episodeTotal"] = ep_count
        item["episodeWatched"] = watched

    # Collections containing this item (manual joins + smart rules).
    item["collections"] = []
    item["smartCollections"] = []
    item_pk = row["Z_PK"]
    for cr in conn.execute(
        "SELECT * FROM ZMEDIACOLLECTION WHERE Z_ENT = ?", (MEDIA_COLLECTION_ENT,)
    ).fetchall():
        is_smart = bool(cr["ZSMARTRULESDATA"])
        rules = _decode_smart_rules(cr["ZSMARTRULESDATA"])
        member_ids = _collection_member_ids(conn, cr["Z_PK"], is_smart, rules)
        if item_pk in member_ids:
            if is_smart:
                item["smartCollections"].append(cr["ZNAME"])
            else:
                item["collections"].append(cr["ZNAME"])
    return item


# -------------------------------------------------------------- insights ---

def _affinity(loved: int, liked: int, disliked: int, rated_count: int, total: int = 0, min_total: int = 0, cutoff: int = 5) -> float:
    """Bayesian-smoothed taste affinity matching the app (prior 0.5, strength 5).

    Loved = 1.0, Liked = 0.5, Disliked = 0. Small samples regress toward 0.5.
    Mirrors TasteMath.affinity(cutoff): requires >= cutoff rated titles, and if
    min_total > 0, also requires >= min_total total titles (used for genreDNA).
    """
    if rated_count < cutoff:
        return 0.0
    if min_total > 0 and total < min_total:
        return 0.0
    s = loved + 0.5 * liked
    return (s + 2.5) / (rated_count + 5.0)


@mcp.tool()
def library_stats() -> dict:
    """Aggregate totals: titles by type/state/taste/mood, completion, watch time."""
    conn = _conn()
    rows = conn.execute(
        "SELECT * FROM ZMEDIAITEM WHERE Z_ENT = ?", (MEDIA_ITEM_ENT,)
    ).fetchall()
    total = len(rows)
    by_type: dict[str, int] = {}
    by_state: dict[str, int] = {}
    by_taste: dict[str, int] = {}
    by_mood: dict[str, int] = {}
    completed = 0
    watch_time = 0
    for r in rows:
        t = r["ZTYPEVALUE"] or "Unknown"
        s = r["ZSTATEVALUE"] or "Unknown"
        ta = r["ZTASTEVALUE"] or "None"
        m = r["ZMOOD"] or "None"
        by_type[t] = by_type.get(t, 0) + 1
        by_state[s] = by_state.get(s, 0) + 1
        by_taste[ta] = by_taste.get(ta, 0) + 1
        by_mood[m] = by_mood.get(m, 0) + 1
        if s == "Completed":
            completed += 1
        watch_time += r["ZCACHEDRUNTIME"] or 0

    return {
        "totalTitles": total,
        "byType": by_type,
        "byState": by_state,
        "byTaste": by_taste,
        "byMood": by_mood,
        "completionRate": round(completed / total * 100, 1) if total else 0,
        "completed": completed,
        "totalWatchTimeMinutes": watch_time,
    }


@mcp.tool()
def genre_dna(limit: int = 15, rank_by: str = "affinity") -> dict:
    """Top genres ranked by taste affinity, matching the app's Insights genreDNA.

    Affinity = (3*loved + liked - 2*disliked) / (3*ratedCount), clamped to 0,
    requiring >=10 titles and >=5 rated per genre. Sorted by affinity desc,
    then title count desc, then name.

    rank_by: 'affinity' (top genres) or 'count' (most-watched genres).
    """
    if rank_by not in ("affinity", "count"):
        return {"error": "rank_by must be 'affinity' or 'count'"}
    conn = _conn()
    rows = conn.execute(
        "SELECT * FROM ZMEDIAITEM WHERE Z_ENT = ?", (MEDIA_ITEM_ENT,)
    ).fetchall()
    stats: dict[str, dict] = {}
    for r in rows:
        for g in decode_plist_array(r["ZCACHEDGENRES"]):
            st = stats.setdefault(g, {"count": 0, "loved": 0, "liked": 0, "disliked": 0, "ratedCount": 0})
            st["count"] += 1
            taste = r["ZTASTEVALUE"]
            if taste == "Love":
                st["loved"] += 1
                st["ratedCount"] += 1
            elif taste == "Like":
                st["liked"] += 1
                st["ratedCount"] += 1
            elif taste == "Dislike":
                st["disliked"] += 1
                st["ratedCount"] += 1

    def affinity(vals: dict) -> float:
        return _affinity(vals["loved"], vals["liked"], vals["disliked"], vals["ratedCount"], vals["count"], min_total=10)

    if rank_by == "count":
        ranked = sorted(
            stats.items(),
            key=lambda kv: (-kv[1]["count"], -affinity(kv[1]), kv[0].lower()),
        )[:limit]
    else:
        ranked = sorted(
            stats.items(),
            key=lambda kv: (-affinity(kv[1]), -kv[1]["count"], kv[0].lower()),
        )[:limit]

    return {
        "rankBy": rank_by,
        "genres": [
            {
                "name": name,
                "count": vals["count"],
                "loved": vals["loved"],
                "liked": vals["liked"],
                "disliked": vals["disliked"],
                "affinity": round(affinity(vals), 3),
                "loveRatio": round(vals["loved"] / vals["count"], 2) if vals["count"] else 0,
            }
            for name, vals in ranked
        ]
    }


@mcp.tool()
def network_studio_analysis(limit: int = 10, rank_by: str = "affinity") -> dict:
    """Top networks/studios, grouped by studio-alias targets when set.

    rank_by: 'affinity' (top by taste affinity) or 'count' (most-watched).
    """
    if rank_by not in ("affinity", "count"):
        return {"error": "rank_by must be 'affinity' or 'count'"}
    conn = _conn()
    rows = conn.execute(
        "SELECT * FROM ZMEDIAITEM WHERE Z_ENT = ?", (MEDIA_ITEM_ENT,)
    ).fetchall()

    # Build source -> target alias map.
    aliases = conn.execute("SELECT * FROM ZSTUDIOALIASENTITY").fetchall()
    source_to_target: dict[str, str] = {}
    for a in aliases:
        target = a["ZTARGET"]
        for s in decode_plist_array(a["ZSOURCES"]):
            source_to_target[s.strip().lower()] = target

    stats: dict[str, dict] = {}
    for r in rows:
        raw = r["ZCACHEDNETWORK"]
        if not raw:
            continue
        is_movie = r["ZTYPEVALUE"] == "Movie"
        taste = r["ZTASTEVALUE"]
        for name in [n.strip() for n in raw.split(",") if n.strip()]:
            grouped = source_to_target.get(name.lower(), name)
            st = stats.setdefault(grouped, {
                "count": 0, "movies": 0, "shows": 0,
                "loved": 0, "liked": 0, "disliked": 0, "ratedCount": 0,
            })
            st["count"] += 1
            if is_movie:
                st["movies"] += 1
            else:
                st["shows"] += 1
            if taste == "Love":
                st["loved"] += 1
                st["ratedCount"] += 1
            elif taste == "Like":
                st["liked"] += 1
                st["ratedCount"] += 1
            elif taste == "Dislike":
                st["disliked"] += 1
                st["ratedCount"] += 1

    def affinity(vals: dict) -> float:
        return _affinity(vals["loved"], vals["liked"], vals["disliked"], vals["ratedCount"])

    kind = "studios" if all(s["movies"] > s["shows"] for s in stats.values()) else "networks"

    if rank_by == "count":
        ranked = sorted(
            stats.items(),
            key=lambda kv: (-kv[1]["count"], -affinity(kv[1]), kv[0].lower()),
        )[:limit]
    else:
        ranked = sorted(
            stats.items(),
            key=lambda kv: (-affinity(kv[1]), -kv[1]["count"], kv[0].lower()),
        )[:limit]

    return {
        "primaryKind": kind,
        "rankBy": rank_by,
        "entries": [
            {
                "name": name,
                "count": vals["count"],
                "movies": vals["movies"],
                "shows": vals["shows"],
                "affinity": round(affinity(vals), 3),
            }
            for name, vals in ranked
        ],
    }


@mcp.tool()
def cast_rankings(limit: int = 10, rank_by: str = "affinity") -> dict:
    """Top cast members or directors/creators by taste affinity or title count.

    rank_by:
      - 'affinity' (top cast by affinity)
      - 'count' (most-watched cast)
      - 'director' (top directors/creators by affinity)
      - 'director_count' (most-credited directors/creators)
    """
    if rank_by not in ("affinity", "count", "director", "director_count"):
        return {"error": "rank_by must be one of affinity, count, director, director_count"}
    conn = _conn()
    rows = conn.execute(
        "SELECT * FROM ZMEDIAITEM WHERE Z_ENT = ?", (MEDIA_ITEM_ENT,)
    ).fetchall()

    scope = "director" if rank_by in ("director", "director_count") else "cast"
    # Directors/creators use a lower floor (4 rated titles) than cast (5),
    # matching the app's creator cutoff.
    aff_cutoff = 4 if scope == "director" else 5
    stats: dict[str, dict] = {}
    for r in rows:
        taste = r["ZTASTEVALUE"]
        if scope == "director":
            names = decode_plist_array(r["ZCACHEDCREATORS"])
        else:
            raw_cast = decode_json_list(r["ZSTOREDCAST"])
            # Top-billed only: 5 for movies, 10 for TV (matches the app's castLimit).
            cast_limit = 5 if r["ZTYPEVALUE"] == "Movie" else 10
            # Exclude Creator/Director roles — the app filters these out of displayCast.
            filtered = [c for c in raw_cast if c.get("characterName") not in ("Creator", "Director")]
            names = [c.get("name") for c in filtered[:cast_limit]]

        for name in names:
            if not name:
                continue
            st = stats.setdefault(name, {"count": 0, "loved": 0, "liked": 0, "disliked": 0, "ratedCount": 0})
            st["count"] += 1
            if taste == "Love":
                st["loved"] += 1
                st["ratedCount"] += 1
            elif taste == "Like":
                st["liked"] += 1
                st["ratedCount"] += 1
            elif taste == "Dislike":
                st["disliked"] += 1
                st["ratedCount"] += 1

    def affinity(vals: dict) -> float:
        return _affinity(vals["loved"], vals["liked"], vals["disliked"], vals["ratedCount"], cutoff=aff_cutoff)

    # Exclude weak matches (affinity < 0.25) — matches the app's Hall of Fame cutoff.
    eligible = {k: v for k, v in stats.items() if affinity(v) >= 0.25}

    by_count = rank_by in ("count", "director_count")
    if by_count:
        ranked = sorted(
            eligible.items(),
            key=lambda kv: (-kv[1]["count"], -affinity(kv[1]), kv[0].lower()),
        )[:limit]
    else:
        ranked = sorted(
            eligible.items(),
            key=lambda kv: (-affinity(kv[1]), -kv[1]["count"], kv[0].lower()),
        )[:limit]

    return {
        "rankBy": rank_by,
        "scope": scope,
        "people": [
            {
                "name": name,
                "count": vals["count"],
                "loved": vals["loved"],
                "liked": vals["liked"],
                "disliked": vals["disliked"],
                "affinity": round(affinity(vals), 3),
                "loveRatio": round(vals["loved"] / vals["count"], 2) if vals["count"] else 0,
            }
            for name, vals in ranked
        ],
    }


@mcp.tool()
def watch_history(limit: int = 20, language: str = "", taste: str = "") -> dict:
    """Most recently interacted titles, optionally filtered by language or taste."""
    conn = _conn()
    rows = conn.execute(
        "SELECT * FROM ZMEDIAITEM WHERE Z_ENT = ? AND ZLASTINTERACTIONDATE IS NOT NULL "
        "ORDER BY ZLASTINTERACTIONDATE DESC",
        (MEDIA_ITEM_ENT,),
    ).fetchall()
    items = [_row_to_item(r) for r in rows]
    if language:
        items = [i for i in items if (i["language"] or "").lower() == language.lower()]
    if taste:
        items = [i for i in items if i["taste"] == taste]
    return {"count": len(items), "items": items[:limit]}


@mcp.tool()
def monthly_watch_activity(year: int = 2026) -> dict:
    """Movies and TV series watched per month in a given year.

    Movies are counted by lastStateChangeDate (the date they were marked
    Completed). TV series are counted by the dates their episodes were actually
    watched (ZTVEPISODE.ZWATCHEDDATE): a show counts toward a month when >=1
    of its episodes was watched that month, and episodes tallies raw watched
    episodes. All months are evaluated in the machine's local timezone to match
    the app's Calendar.current grouping.
    """
    conn = _conn()
    months: dict[str, dict] = {}

    movie_rows = conn.execute(
        "SELECT * FROM ZMEDIAITEM WHERE Z_ENT = ? AND ZTYPEVALUE = 'Movie' AND ZSTATEVALUE = 'Completed'",
        (MEDIA_ITEM_ENT,),
    ).fetchall()
    for r in movie_rows:
        k = local_month_key(r["ZLASTSTATECHANGEDATE"])
        if k and k.startswith(f"{year}-"):
            months.setdefault(k, {"movies": 0, "shows": 0, "episodes": 0})["movies"] += 1

    # Distinct shows with >=1 episode watched per month + raw episode counts.
    # No Z_ENT filter: ZTVEPISODE only contains TVEpisode rows (hardcoding the
    # id breaks when Core Data renumbers Z_ENT).
    show_ids: dict[str, set] = {}
    ep_rows = conn.execute(
        "SELECT * FROM ZTVEPISODE WHERE ZISWATCHED = 1 AND ZWATCHEDDATE IS NOT NULL",
    ).fetchall()
    for e in ep_rows:
        k = local_month_key(e["ZWATCHEDDATE"])
        if k and k.startswith(f"{year}-"):
            month_stats = months.setdefault(k, {"movies": 0, "shows": 0, "episodes": 0})
            month_stats["episodes"] += 1
            show_ids.setdefault(k, set()).add(e["ZSHOWID"])

    for k, ids in show_ids.items():
        months[k]["shows"] = len(ids)

    return {
        "year": year,
        "timezone": "local",
        "months": [
            {"month": k, **months[k]}
            for k in sorted(months)
        ],
    }


@mcp.tool()
def collections() -> dict:
    """List manual and smart collections with computed item counts.

    Smart collections (rule-based) are evaluated dynamically against the library,
    matching how the app computes them — so Thai GL / Watchlist show real members.
    """
    conn = _conn()
    rows = conn.execute(
        "SELECT * FROM ZMEDIACOLLECTION WHERE Z_ENT = ?", (MEDIA_COLLECTION_ENT,)
    ).fetchall()
    out = []
    for r in rows:
        is_smart = bool(r["ZSMARTRULESDATA"])
        rules = _decode_smart_rules(r["ZSMARTRULESDATA"])
        member_ids = _collection_member_ids(conn, r["Z_PK"], is_smart, rules)
        out.append({
            "name": r["ZNAME"],
            "icon": r["ZSYSTEMIMAGE"],
            "isSmart": is_smart,
            "smartRules": rules,
            "isPinned": bool(r["ZISPINNED"]),
            "itemCount": len(member_ids),
        })
    return {"collections": out}


@mcp.tool()
def upcoming_releases(days: int = 90) -> dict:
    """Titles flagged as upcoming with a future release/air date, sorted by date."""
    conn = _conn()
    rows = conn.execute(
        "SELECT * FROM ZMEDIAITEM WHERE Z_ENT = ? AND ZSTOREDISUPCOMING = 1",
        (MEDIA_ITEM_ENT,),
    ).fetchall()
    items = [_row_to_item(r) for r in rows]
    items.sort(key=lambda i: i["nextAiringDate"] or i["releaseDate"] or "")
    return {"count": len(items), "items": items[:days]}


# ------------------------------------------------------------ collection ---

@mcp.tool()
def library_snapshot() -> dict:
    """Compact JSON snapshot of the whole library for context injection."""
    stats = library_stats()
    genres = genre_dna(limit=15)
    networks = network_studio_analysis(limit=10)
    cast = cast_rankings(limit=10)
    return {
        "stats": stats,
        "topGenres": genres["genres"],
        "topNetworksStudios": networks["entries"],
        "topCast": cast["cast"],
        "collections": collections()["collections"],
    }


def main():
    mcp.run()


if __name__ == "__main__":
    main()
