# MediaTracker: Future Intelligence & Experience Roadmap

This plan outlines the implementation details for the next major evolution of MediaTracker, focusing on intelligence, personalization, and deeper system integration.

---

## 1. Smart "Watch Next" Algorithm
**Objective:** Proactively suggest what to watch from your Watchlist based on your personal taste profile.

### Implementation Strategy:
*   **The Taste Engine:** Create a `TasteActor` that builds a "Taste Profile" by analyzing your `Completed` items and `Liked` status. It will weight:
    *   **Genre overlap:** (e.g., You watch a lot of Sci-Fi).
    *   **Cast/Crew consistency:** (e.g., You follow specific directors or actors).
    *   **Network preference:** (e.g., You tend to finish HBO shows more than others).
*   **Scoring Logic:** Every item in your `Watchlist` will be assigned a "Match Score." 
*   **UI:** A new **"For You"** horizontal hero section at the top of the Library grid, showing the top 3-5 matches with a reason why (e.g., *"Because you liked Oppenheimer"*).

---

## 2. Immersive Contextual Theming
**Objective:** Make the app's interface react dynamically to the content you are browsing.

### Implementation Strategy:
*   **Weighted Palette:** When entering a category (e.g., "Horror"), the app will fetch the `themeColorHex` of the top 10 items in that category.
*   **Theme Coordinator:** A new `AppThemeCoordinator` will calculate a "Category Mood" (a soft, desaturated version of the dominant color).
*   **UI Integration:** Apply this mood as a subtle background gradient or sidebar tint using `.background(LinearGradient(...))`. This will use the existing `ColorExtractor` persistence to keep it instant.

---

## 3. Interactive Insights ("The Wrap")
**Objective:** Visualize your media habits through beautiful, interactive charts.

### Implementation Strategy:
*   **Data Aggregator:** An `InsightsManager` that runs a background scan of the library once a day.
*   **Metrics:** 
    *   **Network Distribution:** Percentage of library from Netflix vs. HBO vs. Apple.
    *   **Time Spent:** Sum of runtimes for all `Completed` episodes.
    *   **Genre Clouds:** Most watched genres over time.
*   **UI:** A dedicated **Insights Tab** using SwiftUI `Charts`. It will feature a "Year in Review" style summary that you can view anytime.

---

## 4. "Binge-Mode" Intelligent Sorting
**Objective:** Recognize when a full season drops and prioritize it for the user.

### Implementation Strategy:
*   **Drop Detection:** Enhance the `isTrueFullSeason` logic. When a new season is detected where the first and last episodes air on the same day (Binge Drop), the show is flagged.
*   **Auto-Promotion:** Shows with a fresh "Binge Drop" will be automatically pinned to the top of the **"In Progress"** section for 7 days, even if you haven't started them yet.
*   **UI:** A unique **"Full Season Available"** sparkle badge that glows differently than weekly releases.

---

## 5. macOS Spotlight & System Integration
**Objective:** Make your library searchable and accessible from anywhere on your Mac.

### Implementation Strategy:
*   **CoreSpotlight:** Implement a `SpotlightManager`. When a `MediaItem` is added or updated, we will push its metadata (Title, Overview, Poster) to the macOS system index.
*   **Deep Linking:** Update `App.swift` to handle incoming `NSUserActivity`. Clicking a search result in the Mac's `Cmd + Space` bar will launch MediaTracker directly into that show's `DetailView`.
*   **Widgets:** Create a small "Up Next" widget for the macOS Notification Center showing the 2 most recent upcoming episodes.

---

## Next Steps for Tomorrow:
1.  **Review:** Determine which of these features feels like the "Next Big Thing."
2.  **Prototype:** I recommend starting with **#5 (Spotlight)** as it's a huge "Quality of Life" improvement, followed by **#1 (Smart Watch Next)**.
