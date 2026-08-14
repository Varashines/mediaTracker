# Contributing to MediaTracker

Thanks for helping out! This is a small native macOS app (SwiftUI + SwiftData) with
strict concurrency (`Swift 6`, no external packages).

## Getting started

```bash
swift build              # debug build
swift test               # run tests (XCTest)
```

## Before you open a PR

- Run `swift build` and the relevant test class:
  `swift test --filter <TestCase>`.
- Note: a full-suite test run can hit a known SwiftData in-memory teardown race
  (`ModelContext.save()` after container dealloc) that crashes the process even
  though all assertions pass. Run suites in isolation (or `--filter`) when in
  doubt; it is not a real failure.

## Conventions

- **SwiftData**: always `guard item.modelContext != nil` before model ops; use
  `#Predicate`; use `item.commitChange()` for sync+save+broadcast.
- **Never** call `context.save()` in hot paths — use `SaveCoordinator`.
- Views are `<Feature>View.swift` structs; view models are `@Observable @MainActor`.
- Use `AppTheme` constants — never hardcode colors/spacing/times.
- No comments unless they explain *why*.

## Branch naming

`<topic>-<short-description>` (e.g. `fix/search-cutoff`). PRs merge into `main`.

## GitHub state

- `main` requires the `CI` workflow to pass and linear history.
- API keys live in the macOS Keychain (`KeychainStore`), never `UserDefaults`.
