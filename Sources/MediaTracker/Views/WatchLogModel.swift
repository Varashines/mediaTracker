import Foundation
import SwiftData

/// One row in the watch log: a single pass over a title.
struct WatchLogPass: Identifiable, Equatable, Sendable {
    let id: UUID
    /// "First watch", "Rewatch", …
    let title: String
    let isRewatch: Bool
    let state: WatchCycleState
    let startedAt: Date
    let completedAt: Date?
    /// Distinct episodes (or the single movie) logged in this pass.
    let occurrenceCount: Int
    let runtimeMinutes: Int
    let earliestOccurrence: Date?
    let latestOccurrence: Date?
    /// True when the dates were reconstructed rather than observed.
    let isBackfilled: Bool

    /// Mirrors `WatchCycle.isComplete`, which survives archiving.
    let isCompleteFlag: Bool

    var isFinished: Bool { state == .completed || isCompleteFlag }

    var dateRangeDescription: String? {
        guard let earliestOccurrence else { return nil }
        let end = latestOccurrence ?? completedAt
        let start = min(earliestOccurrence, startedAt)
        guard let end else { return Self.format(start) }
        let sameDay = Calendar.current.isDate(start, inSameDayAs: end)
        return sameDay
            ? Self.format(start)
            : "\(Self.format(start)) – \(Self.format(end))"
    }

    var stateDescription: String {
        if state == .active { return isRewatch ? "Rewatch in progress" : "In progress" }
        if state == .paused { return "Paused" }
        if isCompleteFlag || state == .completed { return "Completed" }
        return "Partial"
    }

    var stateIcon: String {
        switch state {
        case .active: return "play.circle.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .archived: return isCompleteFlag ? "checkmark.circle.fill" : "minus.circle.fill"
        }
    }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

/// Aggregates `WatchCycle` + `WatchEvent` into display rows. Kept separate from
/// the view so the grouping is unit-testable.
enum WatchLogBuilder {
    static func passes(cycles: [WatchCycle], events: [WatchEvent]) -> [WatchLogPass] {
        let activeEvents = events.filter(\.isActive)
        let eventsByCycle = Dictionary(grouping: activeEvents, by: \.cycleID)

        // Rewatch numbering is assigned oldest-first so "Rewatch 2" is the latest
        // pass, and is stable regardless of how the caller sorted the input.
        let ordered = cycles.sorted { $0.startedAt < $1.startedAt }
        var titlesByID: [UUID: String] = [:]
        var rewatchIndex = 0
        for cycle in ordered {
            if cycle.isRewatch { rewatchIndex += 1 }
            titlesByID[cycle.id] = Self.passTitle(isRewatch: cycle.isRewatch, index: cycle.isRewatch ? rewatchIndex : nil)
        }

        return ordered.reversed().map { cycle in
            let cycleEvents = eventsByCycle[cycle.id] ?? []
            let dates = cycleEvents.map(\.watchedAt).sorted()
            let episodeIDs = Set(cycleEvents.compactMap(\.episodeID))
            return WatchLogPass(
                id: cycle.id,
                title: titlesByID[cycle.id] ?? "Pass",
                isRewatch: cycle.isRewatch,
                state: cycle.state,
                startedAt: cycle.startedAt,
                completedAt: cycle.completedAt,
                occurrenceCount: cycle.kind == .movie ? max(cycleEvents.count, 1) : episodeIDs.count,
                runtimeMinutes: cycleEvents.compactMap(\.runtimeMinutes).reduce(0, +),
                earliestOccurrence: dates.first,
                latestOccurrence: dates.last,
                isBackfilled: cycle.isBackfilled || cycleEvents.contains(where: \.isBackfilled),
                isCompleteFlag: cycle.isComplete
            )
        }
    }

    static func passTitle(isRewatch: Bool, index: Int?) -> String {
        guard isRewatch else { return "First watch" }
        guard let index, index > 1 else { return "Rewatch" }
        return "Rewatch \(index)"
    }

    /// Header line: how many passes, how long, and when it all started.
    static func summary(passes: [WatchLogPass], firstWatchedAt: Date?) -> String {
        guard !passes.isEmpty else {
            guard let firstWatchedAt else { return "No watch history yet" }
            return "First watched \(firstWatchedAt.formatted(date: .abbreviated, time: .omitted))"
        }
        let finished = passes.filter(\.isFinished).count
        let totalRuntime = passes.reduce(0) { $0 + $1.runtimeMinutes }
        var parts: [String] = []
        parts.append(finished == 1 ? "1 completed pass" : "\(finished) completed passes")
        if totalRuntime > 0 { parts.append(DateUtils.formatRuntime(totalRuntime)) }
        if let first = passes.compactMap(\.earliestOccurrence).min() {
            parts.append("since \(first.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }
}
