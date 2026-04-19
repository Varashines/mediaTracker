# MediaTracker 🍿📺 [v4.0.0]

MediaTracker is a premium, native macOS application designed for media enthusiasts who demand both aesthetic perfection and functional precision. Built with **SwiftUI** and **SwiftData**, it offers an immersive, "Liquid Glass" experience for tracking your movies and TV shows, staying synchronized with global release schedules, and exploring your collection with unprecedented depth.

## ✨ The Poster Boy Experience

MediaTracker isn't just a database; it's a visual journey. Every corner of the app has been meticulously polished to feel "alive."

- **Immersive Liquid Glass 2.0:** 
    - **Poster-Based Tinting:** The app's background dynamically adapts to the dominant colors of the media you're viewing, creating a beautiful, atmospheric environment.
    - **Smart Opacity:** Tints are calculated to be vibrant yet legible, with opacities optimized for both Light (25%) and Dark (35%) modes.
- **Media Galaxy (Discovery Hub):** 
    - Explore your collection as an organic cluster of **Studios**, **Genres**, and **Languages**.
    - High-resolution studio logos are automatically extracted and color-matched for a premium feel.
- **Precision Branding:** 
    - Choose your app-wide accent color (Indigo, Purple, Mint, etc.).
    - Manual Theme selection (System, Light, Dark) with custom-tinted "Mode Pills" for a tailored UI experience.

## 🚀 Key Functional Features

- **Smart "Now Watching" Section:**
    - A dedicated space for what you're *actually* watching.
    - Automatically populates based on **Last Interaction Date** (toggling episodes, status changes) within a user-configurable window (1-14 days).
- **Advanced "Upcoming" Engine:**
    - **5-Day Relevance Window:** Shows only what's new or imminent for *you*. If you're behind on a show, "Upcoming" noise is automatically hidden.
    - **Dynamic Badging:** Features "Now Streaming" and "Now Available" badges for recently released content.
- **Pro-Grade Search:**
    - **Rich Indexing:** Search your local library by Title, **Director**, **Creator**, **Network**, or **Language**.
    - **Metadata Previews:** Web and local results now display rich metadata (Year • Network/Language • Genre) directly in the search grid.
- **Regional Accuracy:**
    - Specialized logic for **India (IN)** release dates, prioritizing theatrical and digital availability for the region.
- **Detailed TV Tracking:**
    - Full season and episode breakdowns.
    - **Quick Watch:** Mark the next episode as watched directly from the grid with a single click.
    - **Unified Cast & Crew:** Directors and Creators are prepended to the cast list with their high-res profile images.

## 🛠 Technology & Performance

- **Language:** Swift 6.0
- **UI:** Pure SwiftUI (Optimized for macOS 15+)
- **Persistence:** SwiftData with cascading deletes and efficient relationship faulting.
- **Networking:** High-performance Async/Await API clients for **TMDB** & **TVMaze**.
- **Performance Engine:**
    - **Background Refresh:** Metadata automatically scans for updates (new seasons, episode titles) without interrupting the user.
    - **Decoding Pipeline:** Surgical use of `CGImageSource` for memory-efficient image loading.

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
