-- MediaTracker — `date_added` on user_media
--
-- Run in the Supabase SQL editor for the same project the apps sync against.
--
-- Why: `user_media` never carried when a title was added, so Android's "Recently Added" had
-- to approximate it with `last_interaction_date` — which moves on every watch, like and sync,
-- so the section reshuffled whenever anything changed. The Mac already keeps
-- `MediaItem.dateAdded`; this puts it on the wire so Android can order by it (and so rows
-- created before the column existed can adopt the Mac's real added date on the next pull).

alter table user_media add column if not exists date_added timestamptz;

-- Optional seed: give existing rows something better than NULL before the Mac pushes its own
-- dates. Comment out to let each device push its own value instead.
update user_media
   set date_added = coalesce(last_interaction_date, updated_at)
 where date_added is null;
