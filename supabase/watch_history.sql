-- MediaTracker — watch history sync (cycles + events)
--
-- Run in the Supabase SQL editor for the same project the app syncs `user_media` /
-- `user_episodes` / `user_collections` against. Additive: nothing existing changes.
--
-- Model notes:
--   * A `WatchCycle` groups one viewing (a movie's watch, or a show's run). `is_rewatch`
--     marks the second+ cycle, which is what makes "when did I rewatch this" meaningful.
--   * A `WatchEvent` is one immutable watch fact (an episode or a movie at an instant).
--     Rows are only ever voided (`voided_at`), never edited — so the merge is a union keyed
--     by `event_id`, plus a forward-only void.
--   * Ids come from the apps' existing UUIDs, so both devices agree on identity.
--   * `updated_at` is server-owned (trigger) so client clock skew can't order conflicts.

create table if not exists user_watch_cycles (
  user_id           text        not null,
  cycle_id          uuid        not null,
  media_id          text        not null,
  kind              text        not null,          -- "movie" | "tvShow"
  started_at        timestamptz not null,
  completed_at      timestamptz,
  state             text        not null,          -- active | completed | paused | archived
  is_rewatch        boolean     not null default false,
  is_complete       boolean     not null default false,
  scope_episode_ids text[]      not null default '{}',
  is_backfilled     boolean     not null default false,
  updated_at        timestamptz not null default now(),
  primary key (user_id, cycle_id)
);

create table if not exists user_watch_events (
  user_id           text        not null,
  event_id          uuid        not null,
  cycle_id          uuid        not null,
  media_id          text        not null,
  episode_id        text,
  watched_at        timestamptz not null,
  source            text        not null,          -- manual | automatic | imported | migration
  timezone_identifier text,
  runtime_minutes   integer,
  voided_at         timestamptz,
  deduplication_key text        not null,
  is_backfilled     boolean     not null default false,
  updated_at        timestamptz not null default now(),
  primary key (user_id, event_id)
);

-- Pulls are `user_id = eq.<syncKey>` ordered by watched_at / updated_at.
create index if not exists user_watch_cycles_user_updated_idx on user_watch_cycles (user_id, updated_at);
create index if not exists user_watch_events_user_watched_idx on user_watch_events (user_id, watched_at);
create index if not exists user_watch_events_user_updated_idx on user_watch_events (user_id, updated_at);

-- Reuse the server-side updated_at trigger from the collections schema.
-- `search_path` pinned empty to satisfy the security linter (see collections.sql).
create or replace function set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Keep the stamp the source wrote, so every device sees the same "updated" value for a row
  -- rather than each one being re-stamped when it happens to be pushed. Only bound it: a clock
  -- running fast must not push the incremental-pull watermark into the future, or rows written
  -- afterwards would be skipped by both apps until real time caught up.
  new.updated_at = case
    when new.updated_at is null or new.updated_at > pg_catalog.now() then pg_catalog.now()
    else new.updated_at
  end;
  return new;
end;
$$;

drop trigger if exists user_watch_cycles_set_updated_at on user_watch_cycles;
create trigger user_watch_cycles_set_updated_at
  before insert or update on user_watch_cycles
  for each row execute function set_updated_at();

drop trigger if exists user_watch_events_set_updated_at on user_watch_events;
create trigger user_watch_events_set_updated_at
  before insert or update on user_watch_events
  for each row execute function set_updated_at();

-- Row-level security, mirroring the x-sync-key model the apps already send.
alter table user_watch_cycles enable row level security;
alter table user_watch_events enable row level security;

-- Wrap the header lookup in a scalar subquery so the planner hoists it into an InitPlan and
-- evaluates it once per query. Bare inside the filter it is a STABLE call the executor may
-- re-run for every row, which is what the "Auth RLS Initialization Plan" advisor flags.
drop policy if exists user_watch_cycles_sync_key on user_watch_cycles;
create policy user_watch_cycles_sync_key on user_watch_cycles
  for all
  using (user_id = (select nullif(current_setting('request.headers', true), '')::json ->> 'x-sync-key'))
  with check (user_id = (select nullif(current_setting('request.headers', true), '')::json ->> 'x-sync-key'));

drop policy if exists user_watch_events_sync_key on user_watch_events;
create policy user_watch_events_sync_key on user_watch_events
  for all
  using (user_id = (select nullif(current_setting('request.headers', true), '')::json ->> 'x-sync-key'))
  with check (user_id = (select nullif(current_setting('request.headers', true), '')::json ->> 'x-sync-key'));

-- ---------------------------------------------------------------------------
-- Ledger stamps: bound at write, and one viewing recorded twice.
--
-- Same rule as the media tables (see media_tables.sql): `updated_at` keeps the stamp the source
-- wrote — clamped, never overwritten — so every device sees the same "updated" value for a row
-- while a fast clock still can't push the incremental-pull watermark into the future. The events
-- table needs its own function because `watched_at` doesn't exist on the cycle table, which
-- shares `set_updated_at()`.
-- ---------------------------------------------------------------------------

create or replace function set_updated_at_event()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = case
    when new.updated_at is null or new.updated_at > pg_catalog.now() then pg_catalog.now()
    else new.updated_at
  end;
  -- An event can't have been watched after the write that carried it. Android used to format
  -- timestamps from local wall-clock time and label them UTC, so a watch tapped at 16:10 UTC was
  -- recorded as 21:40 "UTC" — hours ahead, and far enough ahead to cross midnight, which put one
  -- viewing on two days in Year in Review.
  new.watched_at = case
    when new.watched_at is null or new.watched_at > pg_catalog.now() then pg_catalog.now()
    else new.watched_at
  end;
  return new;
end;
$$;

drop trigger if exists user_watch_events_set_updated_at on user_watch_events;
create trigger user_watch_events_set_updated_at
  before insert or update on user_watch_events
  for each row execute function set_updated_at_event();

-- Repair events already stamped ahead of their own write, anchoring them to when the row was
-- written. `updated_at` is set explicitly so both apps pull the correction rather than treating
-- the row as unchanged.
update user_watch_events
   set watched_at = least(watched_at, updated_at), updated_at = pg_catalog.now()
 where voided_at is null
   and updated_at is not null
   and watched_at > updated_at;

-- The Doctor X pair: one viewing, logged twice because the two apps spell episode ids
-- differently (`293610_1_3` vs `tv_293610_s1_e3`) and the Android copy was stamped 5½ hours
-- ahead. The client-side dedup now canonicalises ids and compares instants, so this can't
-- recur; these are the three rows it already produced.
update user_watch_events
   set voided_at = pg_catalog.now(), updated_at = pg_catalog.now()
 where event_id in (
   'c89d3756-4469-45d8-8ccd-72a8c1e42af5',   -- tv_293610 s1e3, manual, 21:40:16Z (= 16:10 + 5:30)
   '9116eacb-d654-47de-b023-b90e46b0689d',   -- tv_203857 s4e1, manual, 19:06:54Z (= 13:36 + 5:30)
   '81823be7-3323-4dc8-ad83-4941fff3f4ca'    -- tv_203857 s4e2, manual, 20:16:06Z (= 14:46 + 5:30)
 );

-- Align the episode projections with the surviving events: both carried values from the same
-- mis-stamped pushes (one via the clamp, so its date is the push time rather than the watch).
update user_episodes
   set watched_date = timestamptz '2026-10-16 16:10:16.428+00', updated_at = pg_catalog.now()
 where episode_id = '293610_1_3';

update user_episodes
   set watched_date = timestamptz '2026-10-15 13:36:54.815+00', updated_at = pg_catalog.now()
 where episode_id = '203857_4_1';
