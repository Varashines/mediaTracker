---
name: swiftdata-patterns
description: Correct SwiftData patterns for MediaTracker models, relationships, and context safety
---

## What I do
Ensure SwiftData code follows this project's patterns for models, relationships, fetching, saving, and context safety.

## Model conventions

### Model definition
- Use `@Model final class` for all persistent types
- Use `@Attribute(.unique)` for unique identifiers (e.g., `var id: String`)
- Store enums as raw value strings (e.g., `var typeValue: String` with computed `var type: MediaType?`)
- Cache computed values as stored properties for filtering (e.g., `cachedGenres`, `cachedNetwork`)
- Keep `@Relationship` arrays with explicit `deleteRule: .cascade` for owned children

### Relationship patterns
```swift
// Parent → Child (cascade delete)
@Relationship(deleteRule: .cascade, inverse: \CastMember.movieDetails) var cast: [CastMember] = []

// Many-to-many (e.g., collections)
var collections: [MediaCollection] = []
```

### Context safety — ALWAYS guard before use
```swift
// Before any modelContext operation:
guard item.modelContext != nil else { return }

// In async contexts, also check for deletion:
guard item.modelContext != nil, !item.isDeleted else { return }
```

### Fetching
- Use `FetchDescriptor<T>(predicate: #Predicate { ... })` for type-safe queries
- Always handle optional fetch results: `try? context.fetch(descriptor).first`
- Use `modelContext.model(for: persistentID)` for single-object lookups by `PersistentIdentifier`

### Saving — use SaveCoordinator
- NEVER call `context.save()` directly in hot paths (view body, rapid toggles)
- Use `SaveCoordinator.shared.requestSave(context)` for debounced saves
- Use `SaveCoordinator.shared.forceSave(context)` only when immediate persistence is critical
- Background saves: use `Task.detached` with a dedicated `ModelContext(container)`

### Deletion
- Call `modelContext.delete(item)` then `modelContext.save()`
- Cascade rules handle child cleanup automatically
- Cancel related notifications after deletion: `NotificationManager.shared.cancelNotification(id:type:)`
- Clean up image cache: `ImageCache.shared.removeImage(forKey:)`
- Broadcast state change: `MediaStateService.shared.postMediaStateChanged()`

### Broadcasting changes
- Single item changed: `MediaStateService.shared.postMediaStateChanged(itemID: item.persistentModelID)`
- Bulk change: `MediaStateService.shared.postMediaStateChanged()` (no argument)
- Item refreshed: `MediaStateService.shared.postItemRefreshed(id:persistentID:)`

## When to use me
Use this skill when creating new SwiftData models, modifying relationships, writing fetch/save logic, or handling deletion flows.
