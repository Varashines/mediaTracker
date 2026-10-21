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

-- ---------------------------------------------------------------------------
-- Edit-time repair, then server-owned + clamped timestamps.
--
-- Order matters: the repair below must run while `updated_at` still holds the moment the row
-- was written. Once the triggers exist, `updated_at` is server time and clamping a future edit
-- time to `now()` would leave the bogus value winning against the real edit it was beating.
-- Running this file top to bottom is correct, and on a fresh project the repair is a no-op.
-- ---------------------------------------------------------------------------

-- One-time: anchor any future-dated edit to the row's own write time. A client that edited at a
-- time it could not have reached had made its rows permanently newer, so a later edit on the
-- other device could never win and the skew was re-pushed on every sync.
update user_media
   set last_interaction_date = least(last_interaction_date, updated_at)
 where updated_at is not null
   and last_interaction_date > updated_at;

update user_media
   set last_state_change_date = least(last_state_change_date, updated_at)
 where updated_at is not null
   and last_state_change_date > updated_at;

update user_episodes
   set watched_date = least(watched_date, updated_at)
 where updated_at is not null
   and watched_date > updated_at;

-- Server-owned `updated_at` for the two media tables — the other four sync tables already had
-- this, and its absence here mattered twice over:
--
--   * `updated_at` is what the incremental pull filters on, and both apps derive their stored
--     watermark from the newest such stamp they see. A client whose clock ran fast pushed the
--     watermark into the future, after which every row written later was silently skipped by
--     both apps until real time caught up.
--   * the conflict key on these tables is a user-edit time (`last_interaction_date`), which is
--     a client clock too. Clamping a future value to server time means a fast clock can no
--     longer make one device's rows permanently newer.
--
-- Two functions rather than one: the shared `set_updated_at()` also fires on the watch and
-- collection tables, which have no `last_interaction_date` column for a clamps body to touch.
create or replace function set_updated_at_media()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Keep the stamp the source wrote (see collections.sql): the row's "updated" value should be
  -- the same on every device, bounded only so a fast clock can't skew the pull watermark.
  new.updated_at = case
    when new.updated_at is null or new.updated_at > pg_catalog.now() then pg_catalog.now()
    else new.updated_at
  end;
  new.last_interaction_date = case
    when new.last_interaction_date is null then null
    when new.last_interaction_date > pg_catalog.now() then pg_catalog.now()
    else new.last_interaction_date
  end;
  new.last_state_change_date = case
    when new.last_state_change_date is null then null
    when new.last_state_change_date > pg_catalog.now() then pg_catalog.now()
    else new.last_state_change_date
  end;
  return new;
end;
$$;

-- Episodes key their conflicts on `watched_date`, so it gets the same treatment.
create or replace function set_updated_at_episode()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Keep the stamp the source wrote (see collections.sql): the row's "updated" value should be
  -- the same on every device, bounded only so a fast clock can't skew the pull watermark.
  new.updated_at = case
    when new.updated_at is null or new.updated_at > pg_catalog.now() then pg_catalog.now()
    else new.updated_at
  end;
  new.watched_date = case
    when new.watched_date is null then null
    when new.watched_date > pg_catalog.now() then pg_catalog.now()
    else new.watched_date
  end;
  return new;
end;
$$;

drop trigger if exists user_media_set_updated_at on user_media;
create trigger user_media_set_updated_at
  before insert or update on user_media
  for each row execute function set_updated_at_media();

drop trigger if exists user_episodes_set_updated_at on user_episodes;
create trigger user_episodes_set_updated_at
  before insert or update on user_episodes
  for each row execute function set_updated_at_episode();
