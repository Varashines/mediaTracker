#!/bin/bash
# Snapshot the live SwiftData store to a temp copy so queries never lock the app DB.
set -euo pipefail

STORE="$HOME/Library/Application Support/default.store"
DEST="${1:-/tmp/mediatracker_snapshot.store}"

if [ ! -f "$STORE" ]; then
  echo "error: store not found at $STORE" >&2
  exit 1
fi

cp "$STORE" "$DEST"
echo "$DEST"
