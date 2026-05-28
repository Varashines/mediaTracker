---
name: swift-testing
description: Testing conventions and patterns for MediaTracker XCTest suite
---

## What I do
Ensure new tests follow this project's established XCTest patterns, SwiftData setup, and naming conventions.

## Framework
- Use **XCTest** (not Swift Testing framework)
- Import `@testable import MediaTracker` in every test file
- Test classes: `final class <Feature>Tests: XCTestCase`

## SwiftData test setup
Every test that needs a database must create an in-memory container:
```swift
@MainActor
func makeContainer() -> ModelContainer {
    let schema = Schema([
        MediaItem.self, MovieDetails.self, TVShowDetails.self,
        TVSeason.self, TVEpisode.self, CastMember.self,
        MediaCollection.self, NetworkEntity.self, GenreEntity.self,
        LanguageEntity.self, BadgeEntity.self
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try! ModelContainer(for: schema, configurations: [config])
}
```

## Naming conventions
- Test methods: `test<WhatIsBeingTested><Scenario>` — e.g., `testDeleteMediaItemRemovesFromStore`, `testStandardizeSplitsCompound`
- One assertion topic per test method
- Use `XCTAssertEqual`, `XCTAssertTrue`, `XCTAssertFalse`, `XCTAssertNil`, `XCTAssertNotNil`

## Test organization
- One test file per feature/service: `BackgroundDataServiceTests.swift`, `MediaFilterActorTests.swift`
- Group related tests in the same file
- Use `// MARK: -` sections if a file gets large

## Patterns to follow
- Create fresh container and service in each test (or in `setUp`)
- Use `FetchDescriptor` to verify data was written correctly
- Test both success and failure paths
- For async tests, use `async throws` on the test method
- Use `@MainActor` annotation on tests that interact with SwiftData context

## When to use me
Use this skill when writing new test files, adding test methods, or modifying test infrastructure.
