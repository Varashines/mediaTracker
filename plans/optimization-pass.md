# MediaTracker: "Maximum Smoothness" Optimization Plan

**Objective:** To achieve a 60FPS fluid experience across all main views, even for users with thousands of items, by prioritizing UI snappiness over real-time processing.

---

## 🛑 Phase 1: Strategic Feature Culling (Performance Trade-offs)

To eliminate the "laggy" feeling, we will move away from real-time "on-the-fly" calculations and towards a pre-computed model.

### 1. Simplify "All" Library View
*   **Trade-off:** Remove the "For You" (Taste Engine) section from the top of the "All" library grid.
*   **Why:** Calculating personalized matches requires a full library scan every time the view appears. This doubles the CPU load of the library grid.
*   **Solution:** Restrict "For You" recommendations strictly to the **Home Hub**, where it is expected and processed in the background.

### 2. Static Theme Moods
*   **Trade-off:** Disable the `AppThemeCoordinator` color averaging for general category browsing.
*   **Why:** Extracting dominant colors and averaging them across 10+ items during a scroll causes small but noticeable frame drops.
*   **Solution:** Use the user's selected `appAccent` color as a soft, static background tint for most categories. Keep dynamic moods ONLY for the Home Hero and specific Detail Views.

### 3. Remove "Matched Geometry" from Lists
*   **Trade-off:** Disable `.matchedGeometryEffect` transitions between the grid and detail view for non-hero items.
*   **Why:** Matched geometry forces the UI engine to track every single item's position on screen. With 100+ items, this creates significant layout overhead.
*   **Solution:** Use standard, high-performance slide/fade transitions for a consistent and fast experience.

---

## ⚡️ Phase 2: Technical Hardening (The "Zero-Lag" Core)

### 1. Pre-computed "Smart Flags"
*   **Current Issue:** Computed properties like `isBingeDrop` and `smartBadgeInfo` are calculated on the main thread during grid rendering.
*   **Optimization:** Move these to `@Persisted` properties on the `MediaItem` model. 
*   **Action:** Update them during the background refresh cycle or when a maintenance "Repair" is run. The UI will then simply read a static String/Bool, making grid rendering nearly instantaneous.

### 2. Grid Virtualization Tuning
*   **Action:** Increase the `minimum` width for grid items in `LazyVGrid` and reduce the `spacing`.
*   **Benefit:** Reduces the number of active views the system has to track simultaneously in the viewport.

### 3. Actor Throttling
*   **Action:** Implement a global "Concurrency Governor" that prevents more than one background actor (`HomeFeedActor`, `MediaFilterActor`, etc.) from running if the user is actively scrolling or typing.

---

## 🧼 Phase 3: The "Deep Clean"
*   **Action:** Automate the "Purge Legacy Crew" logic so it runs for the entire library once on the first launch of this update, rather than checking every time a view opens.
*   **Action:** Implement "First-Level Cache" for all networking—storing raw JSON strings on disk to avoid even the 304 Not Modified network overhead for 1 hour.

---

**Execution Priority:** 
1. Pre-computing Smart Flags (Instant Rendering).
2. Removing expensive "For You" from Library Grid (CPU relief).
3. Sidebar/Navigation Debouncing (Interaction Snappiness).