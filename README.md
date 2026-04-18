# MediaTracker 🍿📺 [v2.2.0]

MediaTracker is a premium, native macOS application designed to help you organize and track your movies and TV shows in a beautiful, unified interface. Built with **SwiftUI** and **SwiftData**, it offers a professional-grade experience for managing your library and staying on top of global releases with 100% accuracy.

## 🚀 Key Features

- **Specialized Tracking:** Tailored experiences for Movies and TV Shows.
- **Intelligent Navigation:** Automatically focuses on the first unwatched season or episode.
- **Visual Progress Tracking:**
    - **Progress interpolation:** Dynamic color shifts based on completion percentage.
    - **Quick Watch Button:** Mark the next episode as watched directly from the grid with a single click.
    - **Smart Tooltips:** Hover over the Play Next button to see exactly which episode is being marked (e.g., "S2, Ep4").
- **Discovery Hub:** Explore your collection by **Studio & Network** (with high-res logos) or **Genre** in a dedicated, high-performance grid.
- **Automated Syncing:** 
    - Fetches metadata, genres, and high-res posters via **TMDB**.
    - Tracks global TV schedules and episode titles via **TVMaze**.
- **Performance Optimized:** 
    - Low-level `CGImageSource` decoding for lightning-fast, memory-efficient image loading.
    - GPU-accelerated rendering using `.drawingGroup()` for buttery-smooth scrolling even in massive grids.
    - Smart data caching to eliminate redundant computations.

## 🛠 Recent Improvements

### **v2.2.0: Performance & Fluidity**
- **Surgical Performance Boosts:** Rewrote the image decoding pipeline and optimized the Discovery Hub to ensure 60FPS scrolling.
- **Smart Refresh Engine:** 
    - **Automatic Updates:** The app now scans for metadata updates (new seasons, episode titles) in the background.
    - **Maintenance Mode:** Automatically refreshes TV shows every 30 days (excluding ended/cancelled shows) to keep your library accurate.
- **Visual Refinements:**
    - **Liquid Glass Theme:** A modern, frosted aesthetic that adapts seamlessly to Light and Dark modes.
    - **Enhanced Typography:** Improved 2-line title wrapping for better readability.
    - **Studio Hub Redesign:** Re-engineered the studio card layout for consistent logo scaling and visibility.

### **v2.1.0: Foundation for Fluency**
- **Dynamic Theme Architecture:** poster color extraction for UI tinting.
- **Dual Notifications:** Precise release alerts for upcoming titles.

## 🏗 Technology Stack

- **Language:** Swift 5.10+
- **UI:** SwiftUI (Native macOS Components)
- **Persistence:** SwiftData (SQLite)
- **Search & Indexing:** CoreSpotlight (Cmd+Space support)
- **Notifications:** UserNotifications
- **Networking:** Async/Await API clients for TMDB & TVMaze

## 🚦 Getting Started

### **Prerequisites**
- **macOS 14.0 (Sonoma)** or later.
- **Xcode 15.0+** (if building from source).

### **Installation**
1. Clone the repository.
2. Run `bash install.sh` to build and install to your `/Applications` folder.

### **Configuration**
Provide your own **TMDB API Key** in the **Settings** view to enable metadata syncing and high-resolution posters.

## 📖 Application Architecture

- **Models:** SwiftData-driven schema with cascading deletes and efficient relationships.
- **ViewModels:** Detached `@Observable` logic for clean state management and background processing.
- **DataService:** Centralized management for batch updates, exports, and library maintenance.
- **ImageCache:** Custom persistent disk & memory cache using SHA-256 hashing and automatic pruning.

---
*Built with ❤️ for media enthusiasts.*
