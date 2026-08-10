"""Schema decoding helpers for the MediaTracker SwiftData store.

The store is a Core Data backed SQLite database. This module provides:
- Read-only connection helpers
- Z_ENT -> entity name mapping
- Core Data date decoding (timeIntervalSince2001)
- NSKeyedArchiver binary plist decoding for transformable arrays
"""

import os
import sqlite3
import plistlib
from typing import Any, Optional

# Default store location for the MediaTracker app.
DEFAULT_STORE_PATH = os.path.expanduser("~/Library/Application Support/default.store")

# Core Data stores dates as seconds since 2001-01-01.
COCOA_EPOCH_OFFSET = 978307200.0


class StoreError(Exception):
    """Raised when the store cannot be opened or queried."""


def open_store(path: Optional[str] = None, readonly: bool = True) -> sqlite3.Connection:
    """Open the SwiftData store. Defaults to read-only to never touch live data."""
    store_path = path or DEFAULT_STORE_PATH
    if not os.path.exists(store_path):
        raise StoreError(f"Store not found at {store_path}")
    uri = f"file:{store_path}?mode=ro" if readonly else f"file:{store_path}"
    conn = sqlite3.connect(uri, uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def to_date(value: Optional[float]) -> Optional[str]:
    """Convert a Core Data timestamp to an ISO-8601 string (UTC)."""
    if value is None:
        return None
    import datetime
    return datetime.datetime.fromtimestamp(value + COCOA_EPOCH_OFFSET, tz=datetime.timezone.utc).isoformat()


def decode_plist_array(blob: Optional[bytes]) -> list[str]:
    """Decode an NSKeyedArchiver binary plist that wraps an array of strings.

    Examples: cachedGenres, cachedCreators, cachedWatchProviders.
    """
    if not blob:
        return []
    try:
        obj = plistlib.loads(blob)
    except Exception:
        return []
    # $objects is a list; $top.root references an index holding {"NS.objects": [UID, ...]}
    objects = obj.get("$objects", [])
    try:
        root_idx = obj["$top"]["root"].data
    except Exception:
        root_idx = 1
    if root_idx >= len(objects):
        return []
    container = objects[root_idx]
    if not isinstance(container, dict):
        return []
    refs = container.get("NS.objects", [])
    result: list[str] = []
    for ref in refs:
        idx = ref.data if hasattr(ref, "data") else ref
        if isinstance(idx, int) and idx < len(objects) and isinstance(objects[idx], str):
            result.append(objects[idx])
    return result


def decode_json_list(blob: Optional[bytes]) -> list[dict]:
    """Decode a plain JSON array (used for storedCast)."""
    if not blob:
        return []
    import json
    try:
        data = json.loads(blob.decode("utf-8"))
    except Exception:
        return []
    return data if isinstance(data, list) else []
