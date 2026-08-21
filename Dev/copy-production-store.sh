#!/bin/bash
set -euo pipefail

DEV_STORE_DIRECTORY="${HOME}/Library/Application Support/MediaTracker Dev"
DEV_STORE_PATH="${DEV_STORE_DIRECTORY}/default.store"
SOURCE_STORE_PATH=""
FORCE=false
PRODUCTION_CLOSED=false

usage() {
    cat <<'EOF'
Usage:
  ./Dev/copy-production-store.sh --source /absolute/path/to/default.store --confirm-production-closed [--force]

Creates a snapshot for MediaTracker Dev. The source app must be fully closed so
default.store, default.store-wal, and default.store-shm represent one database state.

Options:
  --source PATH                  Absolute path to the production default.store
  --confirm-production-closed    Required acknowledgement that production is closed
  --force                        Replace an existing MediaTracker Dev snapshot
  --help, -h                     Show this help text
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source)
            SOURCE_STORE_PATH="${2:-}"
            shift 2
            ;;
        --confirm-production-closed)
            PRODUCTION_CLOSED=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$SOURCE_STORE_PATH" || "$SOURCE_STORE_PATH" != /* ]]; then
    echo "Provide an absolute production store path with --source." >&2
    exit 2
fi

if [[ "$PRODUCTION_CLOSED" != true ]]; then
    echo "Refusing to copy a live store. Close MediaTracker, then pass --confirm-production-closed." >&2
    exit 2
fi

if [[ ! -f "$SOURCE_STORE_PATH" ]]; then
    echo "Production store not found: $SOURCE_STORE_PATH" >&2
    exit 1
fi

if [[ -e "$DEV_STORE_PATH" && "$FORCE" != true ]]; then
    echo "Dev store already exists: $DEV_STORE_PATH" >&2
    echo "Use --force to replace it." >&2
    exit 1
fi

mkdir -p "$DEV_STORE_DIRECTORY"
STAGING_DIRECTORY="$(mktemp -d "${DEV_STORE_DIRECTORY}/.snapshot.XXXXXX")"
cleanup() {
    rm -rf "$STAGING_DIRECTORY"
}
trap cleanup EXIT

for suffix in "" "-wal" "-shm"; do
    source_file="${SOURCE_STORE_PATH}${suffix}"
    if [[ -f "$source_file" ]]; then
        cp -p "$source_file" "${STAGING_DIRECTORY}/default.store${suffix}"
    fi
done

if [[ "$FORCE" == true ]]; then
    rm -f "${DEV_STORE_PATH}" "${DEV_STORE_PATH}-wal" "${DEV_STORE_PATH}-shm"
fi

mv "${STAGING_DIRECTORY}/default.store" "$DEV_STORE_PATH"
for suffix in "-wal" "-shm"; do
    if [[ -f "${STAGING_DIRECTORY}/default.store${suffix}" ]]; then
        mv "${STAGING_DIRECTORY}/default.store${suffix}" "${DEV_STORE_PATH}${suffix}"
    fi
done

echo "Dev snapshot created at: $DEV_STORE_PATH"
echo "Launch MediaTracker Dev to test the migration."
