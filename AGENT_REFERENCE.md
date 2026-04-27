# MediaTracker: Agent Quick Reference Guide

Welcome, Agent! This guide is designed to help you quickly understand the architecture and core components of MediaTracker, minimizing the time spent exploring the codebase.

## 🏗 Project Architecture

MediaTracker is a macOS application built with **SwiftUI** and **SwiftData** for media management and tracking.

### Core Data Models (`Sources/MediaTracker/Models.swift`)
- **`MediaItem`**: The central model representing a movie or TV show. Contains metadata like title, rating, overview, and SwiftData-managed attributes.
- **`DiscoveryFilter`**: Defines how media items are filtered in the Discovery Hub (by Studio, Genre, or Language).
- **`DiscoveryNode`**: A UI-friendly model used for grid items in the Discovery Hub (e.g., a language tile or a network logo).
- **`NetworkEntity` / `GenreEntity` / `LanguageEntity`**: SwiftData entities used for caching discovery metadata.

### 🧩 Main Views
- **`MainLibraryView`**: The primary entry point showing the user's saved library.
- **`DiscoveryHubView`**: A dashboard for discovering content through networks, genres, and languages.
- **`ContentView` (Filtered View)**: Dynamically displays a grid of `MediaItem`s based on a `DiscoveryFilter`.
- **`DetailView`**: The comprehensive view for a single `MediaItem`, managed by `DetailViewModel`.
- **`SidebarNavigation`**: Handles the main application navigation structure.

### ⚙️ Logic & Data Services
- **`DataService`**: Handles the main logic for fetching and managing media data from TMDB and other sources.
- **`BackgroundDataService`**: Manages asynchronous updates and background synchronization.
- **`TasteActor`**: Contains the logic for "User Affinity" (calculating which genres, networks, or languages the user prefers based on their library).
- **`Networking.swift`**: Low-level networking layer for API requests.
- **`ImageCache.swift`**: A robust caching system for media posters and backdrops.

### 🛠 Utilities
- **`LanguageUtils`**: Converts ISO language codes (e.g., "en") into localized names (e.g., "English").
- **`DateUtils`**: Formatting and manipulation of dates for release years and tracking.
- **`ColorExtractor`**: Extracts dominant colors from images to provide dynamic UI themes.

## 🚀 Key Workflows
1. **Adding Media**: Handled by `SearchView` -> `DataService` -> SwiftData insertion.
2. **Discovery**: `DiscoveryHubView` fetches cached entities (Networks/Genres/Langs) -> Navigates to `ContentView` with a `DiscoveryFilter`.
3. **Affinity Calculation**: `TasteActor` periodically analyzes the library to update user preferences.

---
*Tip: When debugging filtering issues, check `ContentView.swift`'s `fetchItems()` method and how it interprets `DiscoveryFilter`.*
