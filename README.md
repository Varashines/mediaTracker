# MediaTracker 🍿📺📚 [v2.1.0]

MediaTracker is a premium, native macOS application designed to help you organize and track your movies, TV shows, and books in one beautiful, unified interface. Built with **SwiftUI** and **SwiftData**, it offers a professional-grade experience for managing your library and staying on top of global releases with 100% accuracy.

## Features

- **Multi-Media Support:** Specialized detail views for Movies, TV Shows, and Books.
- **Intelligent Navigation:** Automatically focuses on the first unwatched season or episode, so you never lose your place.
- **Visual Progress Tracking:**
    - **Blue-to-Green Interpolation:** Season tabs dynamically shift color based on completion percentage.
    - **Ongoing Pulse:** Subtle animations highlight seasons you are currently watching.
- **Automated Syncing:** 
    - Fetches metadata, genres, and high-res posters via **TMDB**.
    - Tracks global TV schedules and episode titles via **TVMaze**.
    - Pulls book details and page counts using the **Google Books API**.
- **Interactive Progress:** 
    - Manage your watch history with a per-episode checklist.
    - **Bulk Actions:** Mark entire seasons as watched or unwatched with a single click.
    - **Drag & Drop:** Easily move items between Waitlist, In Progress, and Completed states in the grid.
- **Dual Notifications:** Precise release alerts at the exact moment of availability in India, with follow-up reminders.
- **Universal Search:** Search your local library and the web simultaneously in one unified grid.

## v2.1.0 Improvements: Foundation for Fluency

This update refines the core user experience and prepares the application for high-end macOS animations.

- **Dynamic Theme Architecture:** Improved the hand-off between poster color extraction and UI tinting for faster view loading.
- **Build System v2:** Updated `install.sh` for full v2.1.0 bundle compliance, ensuring seamless Spotlight integration.
- **Refined State Handling:** Optimized the grid to detail transition logic in preparation for Hero-style animations.

## v2.0.0 Highlights

### 🌍 Unified Timing Architecture
Stay synchronized with global releases regardless of where you are.
- **Aggressive Network Rules:** Hardcoded release logic for **Apple TV+**, **Netflix**, **Disney+**, **Amazon Prime**, and **Hulu** to override inconsistent API data.
- **IST & DST Optimized:** Automatically handles Indian Standard Time offsets, including +1 day US-to-India shifts and Daylight Saving Time resilience.
- **Smart Status Headers:** Dynamically displays "Available Now" or "Releases on [Date]" with precision down to the minute.

### 🎭 Cast & Crew
Go behind the scenes with a rich, horizontal-scrolling cast section.
- **Circular Avatars:** Beautifully rendered profile photos for the people behind your favorite media.
- **Character Metadata:** View actor names and their roles at a single glance.
- **Smart Placeholders:** Sleek category icons appear while high-resolution photos are loading.

### 🎨 Modern UI & Experience
Completely redesigned for a faster, more fluid experience.
- **Season & Episode Overhaul:** Navigate long-running shows effortlessly with a horizontal season selector and a modern "square cube" episode grid.
- **Native Inline Search:** A seamless transition from your library to search. Features staggered entrance animations and unified card dimensions.
- **Tabbed Settings:** A professional macOS preference pane with secure API key fields and grouped diagnostic tools.
- **Dynamic Theming:** The entire details page automatically tints itself based on the dominant color of the movie or show's poster.

## Features

- **Multi-Media Support:** Specialized detail views for Movies, TV Shows, and Books.
- **Automated Syncing:** 
    - Fetches metadata, genres, and high-res posters via **TMDB**.
    - Tracks global TV schedules and episode titles via **TVMaze**.
    - Pulls book details and page counts using the **Google Books API**.
- **Interactive Progress:** Manage your watch history with a per-episode checklist and "Full Season" drop detection.
- **Dual Notifications:** Precise release alerts at the exact moment of availability in India, with follow-up reminders.
- **Universal Search:** Search your local library and the web simultaneously in one unified grid.

## Getting Started

### Prerequisites

- **macOS 14.0 (Sonoma)** or later.
- **Xcode 15.0+** (if building from source).

### Installation

To install MediaTracker as a proper macOS application with full notification and Spotlight support:

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/MediaTracker.git
   cd MediaTracker
   ```

2. Run the install script:
   ```bash
   bash install.sh
   ```

The script will build the application in Release mode and move it to your `/Applications` folder.

## Configuration

Provide your own API keys in the **Settings** view to enable live data:

1. **TMDB API Key:** [Get one here](https://www.themoviedb.org/settings/api).
2. **Google Books API Key (Optional):** [Get one from Google Cloud Console](https://console.cloud.google.com/apis/credentials).

## Technology Stack
- **Language:** Swift 5.9+
- **Frameworks:** SwiftUI, SwiftData, UserNotifications, CoreSpotlight
- **Persistence:** SQLite (via SwiftData)
- **APIs:** TMDB (Movies/TV), TVMaze (TV Schedules), Google Books (Books)

## License
[MIT License](LICENSE)
