# MediaTracker Technical Documentation

This document outlines the architectural, logical, and network-related implementations within MediaTracker.

## 🏗 Architecture & State Management

MediaTracker is built using **Swift 6** with a modern **SwiftUI** and **SwiftData** stack, emphasizing performance and thread safety.

- **Persistence Layer:** SwiftData is used for all model storage. Models utilize `@Relationship` for complex hierarchies (TVShow -> Seasons -> Episodes).
- **Concurrent Processing:** 
    - `@ModelActor` (e.g., `BackgroundDataService`, `MediaFilterActor`) is used to perform heavy database operations, filtering, and networking off the Main Actor to prevent UI stutters.
    - `TaskGroup` is employed for parallel execution with controlled concurrency (e.g., 5 simultaneous network requests).
- **State Flow:** The app uses `@Observable` view models (`MediaViewModel`, `DetailViewModel`) to manage UI state, with `MediaThumbnailMetadata` serving as a lightweight bridge between background actors and the view layer.

## 🧠 Core Business Logic

### 1. The Search Engine
The search system is a high-performance "Strict Filter" optimized for local responsiveness.
- **Unified Indexing:** Every `MediaItem` maintains a `searchableText` attribute stored in the database. This index includes the Title, Release Year, Network/Studio, Genres, Languages (code and name), and the top 5 Cast/Crew members.
- **Normalization:** The indexer tokenizes and cleans text (lowercasing, removing colons/dashes) to ensure robust matching across different query styles.
- **Search Scoring:** (Implemented in local filtering) The search engine ranks results based on token matches, ensuring the most relevant items appear first.

### 2. Smart Filtering Logic
The `MediaFilterActor` processes the library using specialized temporal logic:
- **Now Watching:** Items are filtered by the `MediaState.active` status and a user-defined activity window (1–14 days). Sorting is prioritized by `lastUpdated`, bubbling recently interacted items to the top.
- **Upcoming Engine:** Displays content with a `nextAiringDate` in the future or within a 5-day "Recently Released" grace period. It automatically hides "Upcoming" items if the user hasn't caught up, reducing noise.
- **Maintenance Refresh:** TV shows older than 30 days are automatically flagged for a maintenance pass to check for new seasons or status changes (e.g., "Returning Series" to "Ended").

### 3. "Liquid Glass" Visual Engine
- **Dominant Color Extraction:** High-performance color analysis of posters occurs on background threads. Extracted colors are interned via a `StringPool` and cached to minimize memory footprint.
- **Adaptive UI:** The theme engine adjusts background gradients and UI components based on the extracted color, with specific logic to maintain accessibility and legibility in both Light and Dark modes.

## 🌐 Networking & Data Syncing

### 1. Multi-Service API Client
The `APIClient` actor manages communication with two primary data sources:
- **TMDB (The Movie Database):** Primary source for movie/TV metadata, posters, and cast.
- **TVMaze:** Secondary source used for precise episode airing times and global time-zone calculations for TV shows.

### 2. Global Metadata Refresh
A specialized global refresh tool allows for bulk library updates without disrupting user data:
- **metadataOnly Flag:** When active, the app updates high-level metadata (titles, networks, release dates) and rebuilds the search index while explicitly **preserving** episode watched status and the `lastUpdated` sort order.
- **Session Throttling:** To respect API limits and battery life, items are tracked during a session to prevent redundant updates.

### 3. Resilience & Offline Handling
- **Graceful Failure:** The networking layer detects `URLError` and connection failures. Instead of interrupting the user with alerts, the app displays a non-intrusive "Offline" banner and falls back to locally cached search results.
- **Sleep Manager:** The `SleepManager` monitors system activity to pause non-essential networking and data calculations when the app is minimized or the system is idle.

## 📂 Category Arrangement & Calculation

The application organizes media through a multi-layered categorization system, ranging from strict status tracking to dynamic, time-sensitive "Smart Folders."

### 1. Sidebar & Library Organization
The sidebar defines the primary navigational hierarchy, arranged by user intent:
- **Priority Views:** `Upcoming` and `Now Watching` are placed at the top for immediate access to current content.
- **Status Sections:** `In Progress`, `Watchlist`, and `Library` (All) form the core tracking categories.
- **Smart Folders:** Sub-folders for `On Hold`, `Dropped`, and `Re-watching` separate inactive content from the main flow.
- **Media Types:** Automatic grouping by `Movies` and `TV Shows` based on TMDB metadata.

### 2. Dynamic Category Logic
The `MediaFilterActor` dynamically calculates membership for specialized views:
- **Now Watching (Activity-Based):**
    - **Criteria:** Status must be `Active`, it must **not** be in the `Upcoming` window, and it must have been interacted with (watched an episode, changed status, or liked) within the user-defined window (default 2 days).
    - **Sorting:** Sorted by `lastUpdated` descending, ensuring your most recent watch is always first.
- **Upcoming (Date-Based):**
    - **Criteria:** Items with an air date in the future or within a 5-day "Recently Released" window.
    - **Sorting:** Sorted chronologically by the airing date (nearest first).
- **In Progress vs. Watchlist:** 
    - `In Progress` includes any active or re-watching show that is not currently in the "Upcoming" or "Now Watching" state.
    - `Watchlist` strictly shows items marked as `Wishlist` that haven't aired yet or aren't currently being tracked.

### 3. Discovery Hub Aggregation
The "Media Galaxy" (Discovery Hub) provides an analytical view of the library through asynchronous scanning:
- **Aggregation:** The app performs a lightweight background scan of the entire library to extract unique **Studios/Networks**, **Genres**, and **Languages**.
- **Frequency Scoring:** Discovery nodes are sorted primarily by **Frequency** (the number of items you own in that category).
- **Alphabetical Tie-breaking:** If two genres or studios have the same count, they are sorted alphabetically.
- **Logo Matching:** Network nodes prioritize high-resolution logos from TMDB, which are then used for the dynamic theme extraction mentioned in the Visual Engine section.

### 4. User-Defined Sorting
Within most categories, users can manually override the arrangement:
- **Alphabetical:** Standard A-Z sorting by title.
- **Newest Release:** Sorted by the original premiere date (newest first).
- **Recently Added:** Sorted by the date the item was added to the MediaTracker library.
- **Grouping:** Users can toggle "Grouping" to create visual headers for **Years** or **Categories** within their current view.

## 📂 Performance Optimizations
- **String Interning:** A `StringPool` actor ensures that repetitive strings (like "Netflix", "Drama", or "English") share a single memory address across thousands of episodes.
- **Metadata Pre-warming:** The app pre-emptively caches cast profile images for items currently in view to ensure smooth scrolling in detail views.
- **Lazy Grid Rendering:** Grid views use `MediaThumbnailMetadata` structs to avoid faulting thousands of full `MediaItem` objects into memory at once.
