---
name: swift-style
description: Enforce MediaTracker Swift/SwiftUI code conventions and design system usage
---

## What I do
Ensure all Swift code follows this project's established conventions and design system.

## Conventions

### Design System — Always use AppTheme constants
- Spacing: `AppTheme.Spacing.micro`, `.tiny`, `.small`, `.medium`, `.large`, `.xLarge`, `.section`, `.pageMargin`
- Corner radius: `AppTheme.Radius.small`, `.medium`, `.large`, `.card`
- Fonts: `AppTheme.Font.title`, `.title2`, `.title3`, `.heading`, `.body`, `.bodyBold`, `.caption`, `.caption2`, `.small`, `.tiny`, `.badge`
- Shadows: `AppTheme.Shadow.card`, `.elevated`, `.floating`, `.glow`
- Animations: `AppTheme.Animation.springSnappy`, `.springGentle`, `.easeInOut`
- Thumbnails: `AppTheme.Thumbnail.tiny`, `.small`, `.medium`, `.large`, `.compact`
- NEVER hardcode font sizes, spacing values, or corner radii. Always reference AppTheme.

### Time constants — Use TimeInterval extensions
- Use `.days1`, `.days7`, `.days30`, `.days90` instead of raw `86400`
- Use `.secondsInMinute`, `.secondsInHour`, `.secondsInDay` for clarity

### Badge and state constants — Use enums
- Use `SmartBadge.new.rawValue` instead of `"NEW"`
- Use `SmartBadge.radarBadges` set instead of hardcoded `["NEW", "BINGE DROP", ...]`
- Use `MediaState.activeRaw` instead of `"Active"` in `#Predicate` contexts
- Use `MediaType.movieRaw` instead of `"Movie"` in `#Predicate` contexts

### Reusable components — Use existing building blocks
- `HoverScaleEffect()` — for hover interactions with scale + shadow (replaces inline `@State isHovered` + `.onHover` + `.scaleEffect`)
- `GlassCard` — for card containers with material fill + stroke
- `PillBadge` — for capsule badges with icon + text
- `safeSave(context)` — for error-handled saves in MainActor context

### View patterns
- Use `@Observable @MainActor` for view models (not `ObservableObject`)
- Use `@Bindable` for view models in views that need two-way binding
- Use `@Environment(\.modelContext)` for SwiftData context injection
- Views are structs, prefixed with their domain (e.g., `MediaHeaderView`, `TVTrackingView`)
- Use `@ViewBuilder` for computed properties that build complex view hierarchies

### State management
- Use `item.commitChange()` for the sync+save+broadcast pattern (replaces 3-line boilerplate)
- Use `SaveCoordinator.shared.requestSave(context)` for debounced saves — never call `context.save()` directly in hot paths
- Use `ImageCache.shared.ping(url:)` to invalidate image cache when content changes
- Use `FeedbackManager.shared.trigger(.removeFromLibrary)` etc. for haptic feedback

### SwiftData patterns
- Use `MediaItem.thumbnailProperties` or `.thumbnailPropertiesWithCast` for `propertiesToFetch`
- Guard `item.modelContext != nil` before any SwiftData operation
- Use `FetchDescriptor` with `#Predicate` for type-safe queries

### Naming
- View files: `<Feature>View.swift` (e.g., `DetailView.swift`, `SettingsView.swift`)
- View models: `<Feature>ViewModel.swift` (e.g., `DetailViewModel.swift`)
- Services: `<Feature>Service.swift` (e.g., `BackgroundDataService.swift`)
- Use descriptive computed property names over methods when the result is a value

### Error handling
- Surface errors via `AppErrorState.shared.surfaceError("message")`
- Use `AppLogger.debug()`, `AppLogger.info()` for logging
- Background tasks: wrap in `Task.detached` and catch errors

### Color and theming
- Theme colors come from `DetailViewModel.themeColor` / `.vibrantThemeColor`
- Use `.highContrastAccent(colorScheme:)` and `.luminousAccent(colorScheme:)` for accessible colors
- Never use raw `.accentColor` directly — use the theme system

## When to use me
Use this skill when writing new views, modifying existing views, creating view models, or adding UI components. Always verify code matches these conventions before committing.
