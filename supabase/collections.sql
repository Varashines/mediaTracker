-- MediaTracker — collections sync
--
-- Run this in the Supabase SQL editor for the same project the app already syncs
-- `user_media` / `user_episodes` against. It adds the two tables collections need and
-- mirrors the existing `x-sync-key` isolation.
--
-- Model notes:
--   * `collection_id` is the macOS `MediaCollection.id` (a UUID) as text; Android adopts
--     the same id when it first receives a collection, so both sides agree on identity.
--   * `smart_rules` is the JSON of macOS's `SmartRuleSet` ({ matchAny, rules[] }). Smart
--     collections carry rules, not members — their membership is computed per device, so
--     no `user_collection_items` rows are written for them.
--   * `is_deleted` is a tombstone: rows are soft-deleted so a delete propagates, then can
--     be pruned later. `updated_at` is the sync/ordering key (last-writer-wins).

create table if not exists user_collections (
  user_id            text        not null,
  collection_id      text        not null,
  name               text        not null,
  system_image       text        not null default 'folder',
  notes              text,
  is_pinned          boolean     not null default false,
  is_smart           boolean     not null default false,
  smart_rules        text,
  completed_item_ids text[]      not null default '{}',
  is_deleted         boolean     not null default false,
  updated_at         timestamptz not null default now(),
  primary key (user_id, collection_id)
);

create table if not exists user_collection_items (
  user_id       text        not null,
  collection_id text        not null,
  media_id      text        not null,
  is_deleted    boolean     not null default false,
  updated_at    timestamptz not null default now(),
  primary key (user_id, collection_id, media_id)
);

-- Pull is `user_id = eq.<syncKey>` ordered/filtered on updated_at.
create index if not exists user_collections_user_updated_idx
  on user_collections (user_id, updated_at);
create index if not exists user_collection_items_user_updated_idx
  on user_collection_items (user_id, updated_at);

-- Keep updated_at authoritative on the server so client clock skew can't decide conflicts.
-- `search_path` is pinned empty because Supabase's linter flags a mutable one on any
-- function: without it, resolution of an unqualified name inside the body can be steered
-- by whoever runs it. The body touches nothing outside pg_catalog, which is always
-- searched, so pinning costs nothing.
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

drop trigger if exists user_collections_set_updated_at on user_collections;
create trigger user_collections_set_updated_at
  before insert or update on user_collections
  for each row execute function set_updated_at();

drop trigger if exists user_collection_items_set_updated_at on user_collection_items;
create trigger user_collection_items_set_updated_at
  before insert or update on user_collection_items
  for each row execute function set_updated_at();

-- Row-level security.
--
-- This mirrors the `x-sync-key` model the app sends on every request. If your existing
-- `user_media` / `user_episodes` policies use a different expression, copy that one here
-- instead so all four tables stay consistent.
alter table user_collections      enable row level security;
alter table user_collection_items enable row level security;

-- Wrap the header lookup in a scalar subquery so the planner hoists it into an InitPlan and
-- evaluates it once per query. Bare inside the filter it is a STABLE call the executor may
-- re-run for every row, which is what the "Auth RLS Initialization Plan" advisor flags.
drop policy if exists user_collections_sync_key on user_collections;
create policy user_collections_sync_key on user_collections
  for all
  using (user_id = (select nullif(current_setting('request.headers', true), '')::json ->> 'x-sync-key'))
  with check (user_id = (select nullif(current_setting('request.headers', true), '')::json ->> 'x-sync-key'));

drop policy if exists user_collection_items_sync_key on user_collection_items;
create policy user_collection_items_sync_key on user_collection_items
  for all
  using (user_id = (select nullif(current_setting('request.headers', true), '')::json ->> 'x-sync-key'))
  with check (user_id = (select nullif(current_setting('request.headers', true), '')::json ->> 'x-sync-key'));
