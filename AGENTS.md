# MediaTracker

Native macOS media tracking app (SwiftUI + SwiftData). Targets macOS 15+, Swift 6.0 strict concurrency.

## Build & Test

```bash
swift build                          # debug build
swift build -c release               # release build
swift test                           # run all tests (163 tests, XCTest)
swift test --filter <TestCase>       # run single test class
```

Install to /Applications: `bash install.sh` (release) or `bash install.sh --debug`

**Known flaky test:** `SyncCoordinatorTests.testSyncCoordinatorDeduplicates` — 2 assertion failures on main. Investigate before adding sync-related tests.

## Architecture

Single executable target, no packages/dependencies. All code in `Sources/MediaTracker/`.

### Key entrypoints
- `App.swift` — scene setup, model container, theme application
- `ContentView.swift` — `LibraryDetailView` with `NavigationStack`, sidebar routing, filter/pagination
- `MediaViewModel.swift` — central state: navigation, filters, displayed items, discovery caches

### Data layer
- `MediaItem.swift` — core `@Model` with 40+ properties, `syncCachedProperties()` for cache invalidation
- `MediaFilterActor.swift` — filtering/sorting (split into `MediaSorting.swift`, `MediaGrouping.swift`, `HomeCategoryProcessor.swift`)
- `BackgroundDataService.swift` + `BackgroundDataService+Refresh.swift` — API sync, metadata refresh
- `SaveCoordinator.swift` — debounced saves. **Never call `context.save()` in hot paths**
- `MediaStateService.swift` — change broadcasting via count-based invalidation

### View layer
- Views are `<Feature>View.swift` structs, prefixed by domain
- View models use `@Observable @MainActor` (not `ObservableObject`)
- Design system in `AppTheme.swift` — **always use AppTheme constants**, never hardcode values

## Critical Conventions

### SwiftData
- **Always guard** `item.modelContext != nil` before any model operation
- Use `#Predicate` for type-safe queries (raw strings only in `#Predicate` contexts)
- Use `MediaItem.thumbnailProperties` for `propertiesToFetch`
- Use `item.commitChange()` for sync+save+broadcast (replaces 3-line boilerplate)
- Enums stored as raw strings: use `MediaState.activeRaw` etc. in `#Predicate`

### Animations — avoid jitter
- **Never** call `dismiss()` inside `withAnimation` that changes view content
- Close overlays first, then dismiss after delay (`DispatchQueue.main.asyncAfter(deadline: .now() + 0.25)`)
- Defer `MediaStateService.postMediaStateChanged()` until after dismiss animation completes
- Use `AppTheme.Animation.springGentle` or `.springSnappy`

### Theming
- Accent colors via `AppTheme.Colors.accent` (reads `accent_theme_id` from UserDefaults)
- Backgrounds via `AppTheme.Colors.background(for: colorScheme)`
- Card fills via `AppTheme.Colors.cardFill(for: colorScheme)`
- DetailView uses `Color(NSColor.windowBackgroundColor)` — do NOT apply theme background there
- DiscoveryCard uses network's own theme color, not the global accent
- **Theme Transition Delay Bug**: SwiftUI on macOS has a known issue where dynamically transitioning `.preferredColorScheme` from a concrete value (`.light`/`.dark`) to `nil` (to follow the system) fails to immediately update the environment's `\.colorScheme`.
  - *Solution*: In `App.swift`, we subscribe to system appearance changes via `NSApp.publisher(for: \.effectiveAppearance)`. When the theme preference is set to System/Auto (`0`), we compute and return the concrete `systemColorScheme` (either `.dark` or `.light`) rather than `nil`. This forces SwiftUI to immediately redraw the view hierarchy without any lag.

### Time constants
- Use `TimeInterval.days7`, `.days30`, `.secondsInDay` — never raw `86400`

### Reusable components
- `HoverScaleEffect()` — hover with scale + shadow
- `GlassCard` — material fill + stroke container
- `PillBadge` — capsule badge with icon + text
- `safeSave(context)` — error-handled save in MainActor context

## Skills (`.opencode/skills/`)

Four skills loaded on-demand by the agent:
- `swift-style` — AppTheme constants, naming, view patterns
- `swiftdata-patterns` — model conventions, context safety, save/delete patterns
- `animation-debug` — prevent jitter, proper dismiss sequences
- `swift-testing` — XCTest patterns, in-memory container setup
