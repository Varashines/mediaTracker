#!/usr/bin/env python
"""
Apply supabase/collections.sql to the MediaTracker Supabase project.

PostgREST cannot run DDL, and the app only ships a publishable (anon) key, so this needs
one of:

  A) A direct Postgres connection string (Dashboard -> Project Settings -> Database ->
     Connection string -> URI, with your DB password):
         SUPABASE_DB_URL='postgresql://postgres:<pw>@db.kfprelaiidjzecppqhal.supabase.co:5432/postgres' \
           uv run --with psycopg[binary] python supabase/run_sql.py

  B) A Supabase personal access token (Dashboard -> Account -> Access Tokens, `sbp_...`):
         SUPABASE_ACCESS_TOKEN='sbp_...' uv run --with requests python supabase/run_sql.py

Run from the repo root. Idempotent (the SQL uses IF NOT EXISTS / OR REPLACE / DROP POLICY).
"""
import os
import pathlib
import sys

PROJECT_REF = "kfprelaiidjzecppqhal"
SQL_PATH = pathlib.Path(__file__).resolve().parent / "collections.sql"


def main() -> int:
    sql = SQL_PATH.read_text()
    db_url = os.environ.get("SUPABASE_DB_URL", "").strip()
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()

    if db_url:
        import psycopg

        print(f"Applying {SQL_PATH.name} via direct Postgres connection…")
        with psycopg.connect(db_url, autocommit=True) as conn:
            with conn.cursor() as cur:
                cur.execute(sql)
        print("Done.")
        return 0

    if token:
        import requests

        print(f"Applying {SQL_PATH.name} via the Supabase Management API…")
        resp = requests.post(
            f"https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query",
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
            json={"query": sql},
            timeout=60,
        )
        if resp.status_code >= 300:
            print(f"HTTP {resp.status_code}: {resp.text[:400]}", file=sys.stderr)
            return 1
        print("Done.")
        return 0

    print(
        "No credentials. Set SUPABASE_DB_URL (Postgres URI) or SUPABASE_ACCESS_TOKEN (sbp_…).\n"
        "The publishable/anon key the app uses cannot run DDL, and PostgREST has no SQL RPC.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
