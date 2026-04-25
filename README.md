# MediaTracker 🍿📺 [v5.0.0]

MediaTracker is a premium, native macOS application designed for media enthusiasts who demand both aesthetic perfection and functional precision. Built with **SwiftUI** and **SwiftData**, it offers an immersive, "Liquid Glass" experience for tracking your movies and TV shows, staying synchronized with global release schedules, and exploring your collection with unprecedented intelligence.

## ✨ The Premium Experience [New in v5.0]

MediaTracker has evolved from a simple database into an intelligent media hub. Every corner of the app is now faster, smarter, and more reactive.

- **The Home Hub:** 
    - A cinematic landing page featuring your "Featured" recommendation, a "Continue Watching" row with precise status, and a "Coming Soon" timeline for upcoming releases.
    - All data is background-processed for a zero-lag experience.
- **Universal Smart Badges:**
    - The entire library now utilizes intelligent badges: **BINGE**, **FINALE**, **READY TO BINGE**, and **NEW**.
    - These badges automatically detect binge-ready seasons and important series milestones.
- **Immersive Contextual Moods:** 
    - The app's background now dynamically averages the colors of visible media to create a soft, atmospheric "Category Mood" that shifts as you browse.
- **The "Repair Library" Tool:** 
    - A dedicated maintenance utility in Settings that assigns unique identifiers to legacy data, cleans up duplicates, and purges orphaned crew records to keep your database healthy.

## 🚀 Key Functional Features

- **Continue Watching (Smart Filter):**
    - Automatically shows exactly what to watch next for "Active" shows, but *only* if the episode has already aired.
- **Binge-Mode Prioritization:**
    - "In Progress" shows with fresh "Binge Drops" (entire seasons released at once) are automatically bubbled to the top of your list.
- **Smart "Watch Next" (The Taste Engine):**
    - A personalized recommendation algorithm that analyzes your "Completed" and "Liked" content to find hidden gems in your Watchlist.
- **Pro-Grade Search:**
    - Instant indexing by Title, Director, Creator, Network, or Language.
- **Regional Accuracy:**
    - Specialized logic for **India (IN)** release dates, prioritizing theatrical and digital availability for the region.
- **Optimized TV Tracking:**
    - Detailed season/episode breakdowns with "Quick Watch" one-click toggles and stable, text-based creator credits.

## 🛠 Technology & Performance

- **Language:** Swift 6.0 (Strict Concurrency Safe)
- **UI:** Pure SwiftUI (Optimized for macOS 15+)
- **Persistence:** SwiftData with explicit relationships and unique composite identifiers.
- **Networking:** High-performance URLCache with ETag support for 304 "Not Modified" responses, drastically reducing parsing overhead.
- **Performance Engine:**
    - **Background Feed Actors:** Heavy calculations (Home Feed, Discovery, Recommendations) are isolated to background actors to ensure a fluid 60FPS UI.
    - **Debounced Interactions:** Interaction-aware task management prevents lag during rapid typing or navigation.

## 🚦 Getting Started

### **Prerequisites**
- **macOS 15.0 (Sequoia)** or later.
- **Xcode 16.0+** (if building from source).

### **Installation**
1. Clone the repository.
2. Run `bash install.sh` to build and install to your `/Applications` folder.

### **Configuration**
Enter your own **TMDB API Key** in **Settings > General** to enable metadata syncing and high-resolution posters.

---
*Built with ❤️ for those who love cinema as much as code.*
