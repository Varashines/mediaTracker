# MediaTracker

Your entire movie and TV show collection, beautifully organized on your Mac. Track what you've watched, what you're watching, and what's coming next — all in one place.

## What is MediaTracker?

MediaTracker is a native Mac app that helps you keep your viewing life in order. Add movies and TV shows, rate them, mark episodes as watched, and let the app do the rest. It knows your tastes, reminds you about upcoming releases, and tells you what to watch next.

## Home

Your personal dashboard when you open the app:

- **Continue Watching** — Your active shows with unwatched episodes, ready to pick up right where you left off
- **Coming Soon** — Upcoming releases you've added, so you never miss a premiere
- **For You** — Personalized recommendations based on what you've loved and liked
- **Recently Watched** — Quick access to what you've been enjoying

## Track Everything

**Movies & TV Shows** — Add any title from a global database of thousands of movies and shows. Each one comes with a poster, cast info, ratings, and more.

**TV Episode Tracking** — See every season and episode at a glance. Toggle individual episodes as watched, or mark an entire season in one click.

**Media States** — Organize your library the way you want:
- Want to Watch
- Active (currently watching)
- On Hold
- Dropped
- Rewatching
- Completed

**Taste Ratings** — Rate titles as Loved, Liked, or Disliked. These ratings power the recommendation engine and your personal insights.

## Recommendations

MediaTracker uses a multi-layered recommendation engine to help you discover new content:

- **MooreMetrics Integration** — Two-phase recommendation system that analyzes characteristics and preferences to surface relevant titles
- **TasteActor** — Local taste-based matching using genre, creator, cast, and network affinities from your own library
- **Smart Badges** — Intelligent badges that update automatically based on release schedules and viewing progress
- **Continued Watching** — Items you've interacted with recently surface at the top

## Smart Badges

Every item in your library gets an intelligent badge that updates automatically:

- **Premiere** — A new season is about to start
- **Finale** — A season finale is coming up
- **Binge Drop** — A full season just landed at once
- **Binge** — Multiple episodes ready for a marathon
- **Behind** — You're falling behind on episodes
- **New** — Recently added to your library
- **Soon** — Releasing within 48 hours

## Collections

**Manual Collections** — Create your own themed lists. "90s Classics," "Rainy Day Movies," "Comfort Shows" — whatever you like. Pin them to the sidebar for quick access.

**Smart Collections** — Rule-based lists that populate themselves. Set rules like "all completed movies I loved" or "all active shows on Netflix" and watch the collection fill up automatically.

**Quick Add** — Press **Cmd+L** from any detail page to add it to a collection.

## Search

Find anything instantly:

- **Library Search** — Search your own collection by title, cast, creator, network, or language
- **Global Search** — Search the entire database to discover and add new titles
- **Recent Searches** — Your last 10 searches are saved for quick access
- **Year Filter** — Type `y:2023` to narrow results to a specific year

## Release Calendar

A visual calendar that shows you what's releasing and when:

- Heatmap-style overview of release density across the month
- Quick navigation between weeks
- Detailed view for any day showing all your releases
- Color-coded badges for premiere types

## Cinema DNA (Insights)

Discover patterns in your viewing habits:

- **Hero Stats** — Total titles tracked, total watch time, completion rate
- **Taste Profile** — Your love/like/dislike breakdown, top genres, top networks, top studios
- **Cast & Crew** — Actors and creators you watch most
- **Cinephile Lab** — Deep-dive analytics including weekly activity, genre breakdown, release era distribution, and more

## Discovery Hub

Browse and explore by category:

- **Networks & Studios** — See what each streaming service or studio has in your library
- **Genres** — Browse by genre with color-coded cards
- **Languages** — Browse by language
- **Recent Activity** — Filter by smart badges (premieres, finales, binge drops)

## Notifications

Stay on top of new releases:

- Movie premiere alerts
- TV episode air date notifications
- Customizable delivery time (daily digest)
- "Mark as Watched" action directly from the notification

## Settings

Personalize the app:

- **Themes** — Light, Dark, or System mode with Standard, Earth Tones, or Cool Tones palettes
- **Haptic & Audio Feedback** — Tactile and sound responses on interactions
- **Launch at Login** — Open automatically when you start your Mac
- **Prevent Sleep** — Keep your Mac awake during background syncs

## Backup & Restore

Your data stays safe:

- **Export** — Save your entire library as a backup file
- **Import** — Restore from a backup whenever you need to
- **Auto-Backups** — The app keeps rolling backups automatically
- **Database Repair** — Fix duplicates and keep your data healthy

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **Cmd+1–7** | Jump to sidebar sections |
| **Cmd+F** | Open search |
| **Escape** | Dismiss search + clear query |
| **Space** | Mark watched / next episode (in detail view) |
| **W** | Cycle status (in detail view) |
| **Cmd+L** | Add to collection |
| **Cmd+R** | Refresh metadata |
| **Cmd+Delete** | Delete item |

## Toast Feedback

Every action gives you immediate feedback via toasts:

- State changes via keyboard shortcuts
- Taste rating toggles
- Copy title to clipboard
- Add to library
- Mark watched / next episode

## Getting Started

**Requirements:** macOS 14.0 (Sonoma) or later — works on both Apple Silicon and Intel Macs

**Install from source:**
```bash
git clone <repo-url>
bash install.sh
```

**Set up metadata:**
1. Go to **Settings > Connect**
2. Enter your **TMDB API Key** (free at [themoviedb.org](https://www.themoviedb.org/documentation/api))
3. Optional: Add an **OMDb API Key** for Rotten Tomatoes and IMDb ratings

## What Makes It Different

- Native Mac app — fast, responsive, and feels right at home on macOS
- No subscriptions, no accounts, no cloud dependency
- Your data stays on your Mac
- Smart features that learn your taste over time
- Beautiful design that adapts to the media you're browsing

---

*Built for people who love watching as much as tracking what they watch.*
