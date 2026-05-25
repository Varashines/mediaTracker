#!/bin/bash
# Two-phase backfill: TV show content ratings + RT scores from OMDb
#
# Phase 1 — Fetch TMDB external_ids (rate limit: 40 req/10s)
# Phase 2 — Fetch OMDb data (rate limit: 1000/day, free tier)
#
# After Phase 1 creates the JSON file, run with --phase2 to backfill OMDb.
# Phase 2 will save progress to the same JSON and update the database.

DB="$HOME/Library/Application Support/default.store"
TMDB_KEY="5037c7eb861b8a98314d383fd9a4aa53"
OMDB_KEY="aebdf8d6"
JSON_OUT="$HOME/Desktop/tv_imdb_ids.json"
PROGRESS_FILE="$HOME/Desktop/omdb_backfill_progress.json"

mkdir -p "$(dirname "$JSON_OUT")"

get_tmdb_ids() {
    echo "=== Phase 1: Fetching TMDB external_ids for all TV shows ==="

    sqlite3 "$DB" "
        SELECT Z_PK, ZTMDBID FROM ZTVSHOWDETAILS
        WHERE ZCONTENTRATING IS NULL
        ORDER BY Z_PK;
    " | while IFS="|" read -r pk tmdb; do
        echo "  [$pk] TMDB ID $tmdb..."

        RESP=$(curl -s "https://api.themoviedb.org/3/tv/${tmdb}/external_ids?api_key=${TMDB_KEY}" 2>/dev/null)
        IMDB_ID=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('imdb_id','') or '')" 2>/dev/null)

        # Save to JSON array incrementally
        python3 -c "
import json, os
path = '$JSON_OUT'
key = '$tmdb'
imdb = '$IMDB_ID'
pk = $pk

data = {}
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
data[str(key)] = {'pk': pk, 'tmdb_id': int(key), 'imdb_id': imdb, 'content_rating': None, 'rt_score': None, 'omdb_error': None}
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null

        if [ -n "$IMDB_ID" ]; then
            echo "    → imdb_id: $IMDB_ID"
        else
            echo "    → no imdb_id (skipping OMDb)"
        fi

        # Rate limit: max 40 requests per 10 seconds for TMDB
        sleep 0.3
    done

    echo ""
    TOTAL=$(python3 -c "import json; d=json.load(open('$JSON_OUT')); print(len(d))")
    WITH_IMDB=$(python3 -c "import json; d=json.load(open('$JSON_OUT')); print(sum(1 for v in d.values() if v['imdb_id']))")
    echo "=== Phase 1 complete: $TOTAL TV shows scanned, $WITH_IMDB have imdb_id ==="
}

update_omdb() {
    echo "=== Phase 2: Fetching OMDb data ==="
    echo ""

    if [ ! -f "$JSON_OUT" ]; then
        echo "ERROR: Run Phase 1 first to generate $JSON_OUT"
        exit 1
    fi

    python3 -c "
import json

data = json.load(open('$JSON_OUT'))
remaining = [k for k,v in data.items() if v.get('imdb_id') and v.get('content_rating') is None and v.get('omdb_error') is None]
print(f'TV shows with imdb_id needing OMDb: {len(remaining)}')
for k in remaining[:10]:
    v = data[k]
    print(f'  TMDB {k} → imdb_id: {v[\"imdb_id\"]}')
" 2>/dev/null

    echo ""
    if [ "$1" != "--yes" ]; then
        read -p "Continue with OMDb API calls? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
    fi

    python3 -c "
import json, subprocess, time, os

data = json.load(open('$JSON_OUT'))
DB = '$DB'
OMDB_KEY = '$OMDB_KEY'
JSON_OUT = '$JSON_OUT'

to_process = [(k,v) for k,v in sorted(data.items(), key=lambda x: x[1].get('pk',0))
              if v.get('imdb_id') and v.get('content_rating') is None and v.get('omdb_error') is None]

count = 0
success = 0
for key, entry in to_process:
    imdb_id = entry['imdb_id']
    pk = entry['pk']
    print(f'    [{count+1}/{len(to_process)}] TMDB {key} ({imdb_id})...', end=' ', flush=True)

    # Call OMDb API
    result = subprocess.run(
        ['curl', '-s', f'https://www.omdbapi.com?apikey={OMDB_KEY}&i={imdb_id}'],
        capture_output=True, text=True, timeout=15
    )
    raw = result.stdout.strip()

    error = None
    content_rating = None
    rt_score = None

    try:
        resp = json.loads(raw)
        if resp.get('Response') == 'False':
            error = resp.get('Error', 'Unknown error')
        else:
            content_rating = resp.get('Rated')
            ratings = resp.get('Ratings', [])
            for r in ratings:
                if r.get('Source') == 'Rotten Tomatoes':
                    val = r.get('Value', '').replace('%', '')
                    rt_score = int(val) if val.isdigit() else None
    except Exception as e:
        error = str(e)

    if error:
        entry['omdb_error'] = error
        print(f'❌ {error}')
        # If rate limited, stop entirely
        if 'limit' in (error or '').lower():
            print('    Rate limit reached! Saving progress and stopping.')
            with open(JSON_OUT, 'w') as f:
                json.dump(data, f, indent=2)
            break
    else:
        entry['content_rating'] = content_rating
        entry['rt_score'] = rt_score
        success += 1

        # Update database
        if content_rating:
            escaped = content_rating.replace(\"'\", \"''\")
            subprocess.run([
                'sqlite3', DB,
                f\"UPDATE ZTVSHOWDETAILS SET ZCONTENTRATING = '{escaped}' WHERE Z_PK = {pk}\"
            ], capture_output=True)
        if rt_score is not None:
            subprocess.run([
                'sqlite3', DB,
                f\"UPDATE ZTVSHOWDETAILS SET ZROTTENTOMATOESSCORE = {rt_score} WHERE Z_PK = {pk}\"
            ], capture_output=True)

        print(f'✓ R: {content_rating or \"-\"} RT: {rt_score or \"-\"}')

    # Save progress after each call
    with open(JSON_OUT, 'w') as f:
        json.dump(data, f, indent=2)

    count += 1
    # OMDb free tier: ~1 request per second max
    time.sleep(1.5)

print(f'\\nDone. {success} updated, {count - success} failed.')
" 2>/dev/null
}

# Main
if [ "$1" == "--phase2" ]; then
    update_omdb "$2"
else
    get_tmdb_ids
    echo ""
    echo "Phase 1 complete. Saved to $JSON_OUT"
    echo "When OMDb rate limit resets, run:"
    echo "  bash $0 --phase2"
fi
