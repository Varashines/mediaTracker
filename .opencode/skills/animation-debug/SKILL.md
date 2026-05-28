---
name: animation-debug
description: Prevent SwiftUI animation bugs, jitter, and visual glitches in MediaTracker
---

## What I do
Prevent common SwiftUI animation pitfalls that cause jitter, flickering, and visual glitches. This project has had real bugs from competing animations — follow these rules to avoid them.

## Rules

### NEVER compete animations
- Do NOT call `dismiss()` inside or immediately after a `withAnimation` block that changes view content
- The navigation pop animation and content change animation will fight, causing jitter
- Fix: close overlays first (set state to false), THEN dismiss after a delay

### Proper dismiss sequence
```swift
// WRONG — causes jitter
withAnimation {
    isDeleted = true
}
dismiss()

// CORRECT — clean exit
showDeleteConfirmation = false  // close overlay first
DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
    dismiss()  // dismiss after overlay exit animation
}
```

### Defer state broadcasts during animations
- Do NOT call `MediaStateService.shared.postMediaStateChanged()` while a dismiss animation is in flight
- The broadcast triggers a library grid re-render that compounds the visual glitch
- Fix: add a sleep before broadcasting (e.g., `try? await Task.sleep(for: .seconds(0.3))`)

### Animation modifiers on conditional content
- If a view is conditionally swapped (`if/else`), animating modifiers on the old view won't animate the transition to the new view
- Use `.transition()` on the incoming/outgoing view instead
- Or use `withAnimation` on the state change that controls the condition

### Scale/opacity effects on scrollable content
- Do NOT combine `.scaleEffect` with navigation transitions — the scale animation interferes with the nav pop
- Use `.saturation` or `.opacity` for dimming effects instead of scale

### One animation per trigger
- Avoid stacking multiple `withAnimation` calls that trigger on the same state change
- Use `AppTheme.Animation.springGentle` or `.springSnappy` for consistent feel
- Use `AppTheme.Animation.easeInOut` for subtle transitions

### Timeline for sequential animations
```swift
// Step 1: Close overlay (no animation needed, just state change)
showDeleteConfirmation = false

// Step 2: Wait for overlay exit, then dismiss
DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
    dismiss()
}

// Step 3: Wait for dismiss to complete before broadcasting
Task {
    try? await Task.sleep(for: .seconds(0.5))
    MediaStateService.shared.postMediaStateChanged()
}
```

## When to use me
Use this skill when adding, modifying, or debugging any SwiftUI animation, transition, or visual effect. Especially important for modal overlays, delete confirmations, sheet presentations, and navigation transitions.
