# MediaTracker 🍿📺📚

MediaTracker is a powerful, native macOS application designed to help you organize and track your movies, TV shows, and books in one beautiful, unified interface. Built with **SwiftUI** and **SwiftData**, it offers a seamless experience for managing your personal library and staying on top of upcoming releases.

## Features

- **Multi-Media Support:** Track Movies, TV Shows, and Books with specialized detail views for each.
- **Automated Syncing:** 
    - Fetches movie runtimes, genres, and release dates via **TMDB**.
    - Tracks TV show statuses, next episode dates, and season progress via **TVMaze** and **TMDB**.
    - Pulls book details and page counts using the **Google Books API**.
- **Smart Upcoming View:** Automatically categorizes items that are "Available Now" or "Releasing Soon" based on precise airing times.
- **Dual Notifications:** Never miss a premiere with automatic 1:30 PM release day alerts and 9:30 AM "In case you missed it" reminders the following day.
- **TV Tracking:** Manage season progress with an interactive episode-by-episode checklist.
- **Beautiful Grid Interface:** View your library with high-quality posters, status badges, and drag-and-drop category management.
- **Secure Configuration:** Keep your API keys safe with integrated AppStorage and a dedicated Settings view.

## Getting Started

### Prerequisites

- **macOS 14.0 (Sonoma)** or later.
- **Xcode 15.0+** (if building from source).

### Installation

To install MediaTracker as a proper macOS application with full notification support, use the provided installation script:

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/MediaTracker.git
   cd MediaTracker
   ```

2. Run the install script:
   ```bash
   bash install.sh
   ```

The script will build the application in Release mode, package it into `MediaTracker.app`, and move it to your `/Applications` folder.

## Configuration

To enable data fetching, you will need to provide your own API keys in the **Settings** view:

1. **TMDB API Key:** [Get one here](https://www.themoviedb.org/settings/api).
2. **Google Books API Key (Optional):** [Get one from Google Cloud Console](https://console.cloud.google.com/apis/credentials).
3. **TVMaze:** No API key required for public lookups.

## Development Notes

### Xcode Debugging
When running directly from Xcode (SPM mode), the application is not running in a signed `.app` bundle. To prevent crashes, the `NotificationManager` will automatically disable notification requests and log a warning to the console. 

**Note:** To test notifications, you must use the `install.sh` script to build and sign the app properly.

### Technology Stack
- **Language:** Swift 5.9+
- **Frameworks:** SwiftUI, SwiftData, UserNotifications
- **Persistence:** SQLite (via SwiftData)
- **APIs:** TMDB (Movies/TV), TVMaze (TV Schedules), Google Books (Books)

## License
[MIT License](LICENSE)
