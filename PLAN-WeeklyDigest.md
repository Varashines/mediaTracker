# Plan — Weekly Digest (v9 "Arc")

A weekly notification summarizing what you watched that week: **number of shows
and movies** (the core ask), with the option to name top titles.

## What it is
- One **local** repeating notification per week (no network).
- Content: "Your week in review — **5 shows · 3 movies** watched." (Maybe a top
  title or two appended.)
- Configurable day/time in Settings (default Sunday evening), toggle on/off.

## Data (all local, existing fields)
- **Shows watched this week** = distinct TV shows with ≥1 episode `watchedDate`
  in the last 7 days (`seasonNumber > 0`, matching the Year-in-Review rule).
- **Movies watched this week** = movies with `lastStateChangeDate` in the last
  7 days (state `Completed`).

## Phases

### Phase 1 — `WeeklyDigestService` (model layer)
- `@ModelActor` with `digest(for date: Date) -> WeeklyDigest`:
  `WeeklyDigest { shows: Int, movies: Int, topTitles: [String] }`.
  - Counts via `#Predicate` on the 7-day window (episodes + completed movies).
  - Top titles: pick the 2–3 most-watched shows by episode count for the message.
- Reuses the same window rule as `YearInReviewService` (season 0 excluded).
- Unit tests: counts within a 7-day window, boundary exclusion, specials
  excluded, empty week.

### Phase 2 — Scheduling (`NotificationManager`)
- Add a **weekly repeating trigger** (`UNCalendarNotificationTrigger` with
  `weekday` + hour/minute) that, when it fires, computes the digest and shows
  the notification with counts. (Local only — no push.)
- Regenerate on Settings change (day/time/toggle).
- Cancel when disabled.

### Phase 3 — Settings toggle (`ServicesSection`)
- "Weekly Digest" row in the Notifications card: on/off toggle + day + time
  pickers (default: Sunday 7:00 PM).
- Mirrors the existing notification settings pattern.

## Message copy (draft)
- Counts: "This week you watched **5 shows and 3 movies**."
- With titles: "…including *The Office* and *Project Hail Mary*."
- Tapping opens the app.

## Acceptance
- One notification per week with correct show/movie counts.
- Toggle + day/time work; disabling cancels pending digest.
- Build + unit tests green.

## Non-goals
- No per-episode detail, no images, no push infrastructure.
