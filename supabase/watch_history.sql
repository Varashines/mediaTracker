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
  new.updated_at = pg_catalog.now();
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
