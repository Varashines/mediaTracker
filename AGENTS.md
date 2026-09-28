# MediaTracker

Native macOS media tracking app (SwiftUI + SwiftData). Targets macOS 15+, Swift 6.0 strict concurrency.

## Build & Test

```bash
swift build                          # debug build
swift build -c release               # release build
swift test                           # run all tests (XCTest)
swift test --filter <TestCase>       # run single test class
swift test --filter "BadgeEngineTests|DetailViewModelTests"  # run multiple test classes
```

**Note**: `DiscoverySyncServiceTests/testNetworkCountDeduplication` previously made **real network calls** (via `extractMissingColors`); it is now stubbed with `MockURLProtocol` (through `ImageCache.configureForTesting`) and is deterministic/fast in isolation. A **separate, general SwiftData in-memory-container teardown autosave race** can still crash a *full-suite* run (`ModelContext.save() called after its ModelContainer has been deallocated`). All assertions pass — it is a SwiftData issue, not a real failure.

### GitHub workflows
- `.github/workflows/release.yml` — triggers on `v*` tags; builds both-arch DMGs **and creates a public GitHub Release**.
- `.github/workflows/build-only.yml` — manual `workflow_dispatch`; builds both-arch DMGs and uploads them as **artifacts only** (no release). Version is a workflow input.
- `.github/workflows/ci.yml` — the `build-and-test` gate. Required on `main`, so a release push must land on a green `develop`.

### Release process
`develop` is the integration branch; `main` is the release branch. Releases go through a PR so every release has an auditable checkpoint with CI and approval on the release itself.

```bash
# 1. feature work
git switch develop && git pull
git switch -c feature/my-change        # branch off develop
# ... make changes, commit per phase ...
git push -u origin feature/my-change

# 2. verify with a real both-arch build before merging
gh workflow run build-only.yml --ref feature/my-change -f version=9.6.4
gh run watch <run-id> --exit-status

# 3. merge to develop
gh pr create --base develop --head feature/my-change
gh pr merge <n> --squash

# 4. bump the version (only when planning a release)
#    MARKETING_VERSION in project.yml, both targets, on its own branch -> PR -> develop

# 5. release: develop -> main via PR, then tag
gh pr create --base main --head develop
gh pr merge <n> --squash               # squash or rebase; NOT a merge commit (see below)
git tag -a v9.6.4 -m "Release v9.6.4: …" && git push origin v9.6.4
```

**Notes:**
- `main` has `required_linear_history` enabled, so a release PR **must** be squashed or rebased. A merge commit will be rejected.
- The release tag fires `.github/workflows/release.yml`, which publishes the GitHub Release and both DMGs.
- `main...develop` normally reads `0  <n>` with a non-zero count. That is **expected**: each release PR mints new commits on `main`, so the same change exists under two hashes (the squash twin on `main`, the original on `develop`). The trees are identical and nothing is stranded. It is cosmetic — do not force-push either branch to chase a `0  0`.
- Because of that, cherry-picking between branches needs the PR number rather than the raw SHA.
- Do not merge `main` back into `develop`. A merge commit in `develop` is what makes *"This branch can't be rebased"* appear on later PRs.

**Health check:**

```bash
git rev-list --left-right --count origin/main...origin/develop   # expect "0  <n>"
git diff --stat origin/main origin/develop                        # should be empty when nothing is pending
```

## Architecture

Single executable target, no packages/dependencies. All code in `Sources/MediaTracker/`.

### Key entrypoints
- `App.swift` — scene setup, model container, theme application, biometric app-lock gate
- `ContentView.swift` — `LibraryDetailView` with `NavigationStack`, sidebar routing, filter/pagination
- `MediaViewModel.swift` — central state: navigation, filters, displayed items, discovery caches

### Data layer
- `MediaItem.swift` — core `@Model` with 40+ properties, `syncCachedProperties()` for cache invalidation
- `MediaFilterActor.swift` — filtering/sorting (split into `MediaSorting.swift`, `MediaGrouping.swift`, `HomeCategoryProcessor.swift`)
- `BackgroundDataService.swift` + `BackgroundDataService+Refresh.swift` — API sync, metadata refresh, per-season cast
- `SeasonCastMember.swift` — per-season aggregate cast (`/tv/{id}/season/{n}/aggregate_credits`), linked to `TVSeason`
- `TasteMath.swift` — central taste math: title-weight tiers, season weights, effective-season-taste rule
- `AppLockService.swift` — biometric (Touch ID) app lock, lock on launch/inactive
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
- **Transition Delay for Progressive Content**: For detailed/heavy statistical screens (e.g., `InsightsView`), use a sleep of `try? await Task.sleep(nanoseconds: 350_000_000)` (350ms) to allow the macOS navigation slide-in animation to complete showing a shimmering skeleton (`.shimmering()`) before rendering the final layout.

### Theming
- Accent colors via `AppTheme.Colors.accent` (reads dynamically from `AppThemeCoordinator.shared.accent`)
- Backgrounds via `AppTheme.Colors.background(for: colorScheme)` (delegated to `AppThemeCoordinator.shared.background`)
- Card fills via `AppTheme.Colors.cardFill(for: colorScheme)` (delegated to `AppThemeCoordinator.shared.cardFill`)
- DetailView uses `AppTheme.Colors.background(for: colorScheme)` — integrates custom theme backgrounds with vibrant poster overlays
- DiscoveryCard uses network's own theme color, not the global accent
- **Custom Palettes**: Supports standard Accent (0), Earth Tones (1), Cool Tones (2), Forest (3), Ocean (4), Dusk (5), and Midnight (6) resolved and propagated dynamically via the `@Observable AppThemeCoordinator`. Apply these to views using the `.adaptiveBackground()` modifier.
- **Layout Squeezing Constraint**: In Settings panels, avoid horizontal layouts (side-by-side labels and wide pickers) that cause label text to wrap/clipping. Stack forms vertically (labels above pickers) to prevent truncation.
- **Theme Transition Delay Bug**: SwiftUI on macOS has a known issue where dynamically transitioning `.preferredColorScheme` from a concrete value (`.light`/`.dark`) to `nil` (to follow the system) fails to immediately update the environment's `\.colorScheme`.
  - *Solution*: In `App.swift`, we subscribe to system appearance changes via `NSApp.publisher(for: \.effectiveAppearance)`. When the theme preference is set to System/Auto (`0`), we compute and return the concrete `systemColorScheme` (either `.dark` or `.light`) rather than `nil`. This forces SwiftUI to immediately redraw the view hierarchy without any lag.
- **Reactive Theme & Palette Updates**: Static color queries normally do not register SwiftUI layout dependencies.
  - *Solution*: `AppTheme.Colors` properties read from the `@Observable @MainActor class AppThemeCoordinator`, which observes `UserDefaults.didChangeNotification`. When preference changes are detected, the coordinator updates its reactive properties, instantly forcing SwiftUI to redraw any view referencing these color tokens.

### Button Hit-Testing
- **`.buttonStyle(.plain)` strips hit targets** — buttons only respond to taps on their label content, not the padded area. Always add `.contentShape(Capsule())` or `.contentShape(Rectangle())` after padding/background on button labels. This affects ~40 buttons across the app.

### SVG Logo Support
- `ImageCache.swift` uses `NSImage(data:)` to render SVGs (macOS 14+ private API `_NSSVGImageRep`). When `CGImageSource` fails for SVG data, it falls back to `renderSVGToCGImage` via NSImage.
- `Networking.swift` sorts SVGs first in `processLogoURLs()` and fetches at `w780` resolution for crisp display.
- `TitleSection.swift` displays logos at `CGSize(width: 780, height: 185)` — matched to source resolution to avoid upscale blur.

### Navigation Transitions
- **`matchedGeometryEffect` does NOT work with NavigationStack push/pop on macOS** — the source view is not preserved during the push animation. The only official solution is `.navigationTransition(.zoom(...))` which is iOS-only.
- The hero poster transition from grid to detail view currently uses the default NavigationStack slide. The `matchedGeometryEffect` on poster views is wired but inactive for push — it only animates during pop.

### Keyboard Shortcuts & Interactions
- **Contextual Shortcuts**: The spacebar shortcut (`.keyboardShortcut(.space, modifiers: [])`) in the detail view is contextual:
  - TV Shows: Marks the next unwatched episode as seen via `viewModel.markNextEpisodeWatched()` and triggers haptic `.markWatched`.
  - Movies: Toggles overall completion via `viewModel.toggleWatched()` and triggers haptic `.markWatched` / `.stateChange`.
- **Status Cycling**: Use the `w` shortcut to cycle state (`viewModel.cycleStatus()`) with haptic responses.
- **Back Shortcut** (`Cmd + Left`): Global handler in `ContentView` pops a pushed detail first, then exits the current collection (`selectedCollectionID = nil`). `FilteredLibraryGridView` has its own local Cmd+Left that pops the filtered grid.

### Time constants
- Use `TimeInterval.days7`, `.days30`, `.secondsInDay` — never raw `86400`

### Reusable components
- `HoverScaleEffect()` — hover with scale + shadow
- `GlassCard` — material fill + stroke container
- `PillBadge` — capsule badge with icon + text
- `safeSave(context)` — error-handled save in MainActor context
