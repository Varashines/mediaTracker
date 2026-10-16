-- MediaTracker — base schema for `user_media` and `user_episodes`
--
-- Run in the Supabase SQL editor for the same project the apps sync against.
--
-- Why this file exists: both tables (with their RLS) were created by hand in the dashboard, so
-- nothing in this directory reproduced them — a fresh project came up with four of the six sync
-- tables and no way to recreate the other two. This mirrors the live definition, with two
-- deliberate corrections:
--
--   * the `(user_id, updated_at)` indexes below were missing in production, so every
--     watermarked pull — `user_id = … AND updated_at > …`, which runs every 30 minutes —
--     fell back to walking the whole partition for that user (17–19 ms mean, up to 217 ms);
--   * `user_media`'s policy carried `with check (length(user_id) >= 12)` instead of the key
--     check the other five tables use, which is the one place a client could write a row
--     under a different tenant's `user_id`.
--
-- Run order for a fresh project: media_tables.sql → collections.sql → watch_history.sql.
-- (media_date_added.sql is folded in here, and stays a harmless no-op for existing projects.)

create table if not exists user_media (
  user_id                text not null,
  media_id               text not null,
  type                   text not null,
  state                  text not null,
  taste                  text not null default 'None',
  custom_poster_url      text,
  is_soft_deleted        boolean default false,
  last_interaction_date  timestamptz,
  last_state_change_date timestamptz,
  updated_at             timestamptz default now(),
  date_added             timestamptz,
  primary key (user_id, media_id)
);

create table if not exists user_episodes (
  user_id        text not null,
  episode_id     text not null,
  show_id        text not null,
  season_number  integer not null,
  episode_number integer not null,
  is_watched     boolean not null default false,
  watched_date   timestamptz,
  updated_at     timestamptz default now(),
  primary key (user_id, episode_id)
);

-- The pull filters on user_id and updated_at and orders by updated_at, so one index answers
-- both the range and the sort. `updated_at` is indexed on every sync table for this reason.
create index if not exists user_media_user_updated_idx    on user_media    (user_id, updated_at);
create index if not exists user_episodes_user_updated_idx on user_episodes (user_id, updated_at);

alter table user_media    enable row level security;
alter table user_episodes enable row level security;

-- Same x-sync-key policy as the other four tables. The header lookup is wrapped in a scalar
-- subquery so the planner hoists it into an InitPlan and evaluates it once per query rather
-- than once per row.
--
-- The drops cover the dashboard's auto-generated names too: on an existing project these
-- tables have `Secret key access for user_media` / `…user_episodes`, and leaving both would
-- mean two permissive policies per table (the media one with the loose check above).
drop policy if exists "Secret key access for user_media"    on user_media;
drop policy if exists "Secret key access for user_episodes" on user_episodes;
drop policy if exists user_media_sync_key    on user_media;
drop policy if exists user_episodes_sync_key on user_episodes;

create policy user_media_sync_key on user_media
  for all
  using (user_id = (select nullif(current_setting('request.headers', true), '')::json ->> 'x-sync-key'))
  with check (user_id = (select nullif(current_setting('request.headers', true), '')::json ->> 'x-sync-key'));

create policy user_episodes_sync_key on user_episodes
  for all
  using (user_id = (select nullif(current_setting('request.headers', true), '')::json ->> 'x-sync-key'))
  with check (user_id = (select nullif(current_setting('request.headers', true), '')::json ->> 'x-sync-key'));
