import SwiftData
import SwiftUI

struct WatchHistorySummary: Equatable, Sendable {
    let cycleCount: Int
    let completedCycleCount: Int
    let completedRewatchCount: Int
    let activeRewatchCount: Int
    let pausedRewatchCount: Int
    let archivedPartialRewatchCount: Int

    init(cycles: [WatchCycle]) {
        cycleCount = cycles.count
        completedCycleCount = cycles.filter { cycle in
            cycle.isComplete || cycle.state == .completed
        }.count
        completedRewatchCount = cycles.filter { cycle in
            cycle.isRewatch && (cycle.isComplete || cycle.state == .completed)
        }.count
        activeRewatchCount = cycles.filter { cycle in
            cycle.isRewatch && cycle.state == .active
        }.count
        pausedRewatchCount = cycles.filter { cycle in
            cycle.isRewatch && cycle.state == .paused
        }.count
        archivedPartialRewatchCount = cycles.filter { cycle in
            cycle.isRewatch && cycle.state == .archived && !cycle.isComplete
        }.count
    }

    var hasCompletedHistory: Bool { completedCycleCount > 0 }
    var hasRewatchHistory: Bool { completedRewatchCount > 0 }
    var hasInProgressRewatch: Bool { activeRewatchCount > 0 || pausedRewatchCount > 0 }
    var hasPartialRewatch: Bool { hasInProgressRewatch || archivedPartialRewatchCount > 0 }
    var hasInProgressFirstWatch: Bool { !hasCompletedHistory && !hasPartialRewatch }
}

struct WatchHistorySummaryView: View {
    @Query private var cycles: [WatchCycle]
    @Environment(\.colorScheme) private var colorScheme

    init(mediaID: String) {
        _cycles = Query(
            filter: #Predicate<WatchCycle> { cycle in
                cycle.mediaID == mediaID
            },
            sort: [SortDescriptor(\WatchCycle.startedAt, order: .reverse)]
        )
    }

    var body: some View {
        let summary = WatchHistorySummary(cycles: cycles)
        if summary.cycleCount > 0 {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.small) {
                    summaryPills(summary)
                }
                FlowLayout(spacing: AppTheme.Spacing.small) {
                    summaryPills(summary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(summaryAccessibilityLabel(summary))
        }
    }

    @ViewBuilder
    private func summaryPills(_ summary: WatchHistorySummary) -> some View {
        if summary.hasCompletedHistory {
            summaryPill(
                icon: "checkmark.circle.fill",
                text: summary.completedCycleCount == 1 ? "Watched once" : "Watched ×\(summary.completedCycleCount)"
            )
        }
        if summary.hasRewatchHistory {
            summaryPill(
                icon: "arrow.clockwise",
                text: summary.completedRewatchCount == 1 ? "Rewatched once" : "Rewatched ×\(summary.completedRewatchCount)"
            )
        }
        if summary.activeRewatchCount > 0 {
            summaryPill(icon: "play.circle.fill", text: "Rewatch in progress")
        }
        if summary.pausedRewatchCount > 0 {
            summaryPill(icon: "pause.circle.fill", text: "Rewatch paused")
        }
        if summary.archivedPartialRewatchCount > 0 {
            summaryPill(icon: "minus.circle.fill", text: "Partial rewatch")
        }
        if summary.hasInProgressFirstWatch {
            summaryPill(icon: "circle.dotted", text: "Watch in progress")
        }
    }

    private func summaryPill(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(AppTheme.Font.caption2.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.75))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, AppTheme.Spacing.small)
            .padding(.vertical, AppTheme.Spacing.micro)
            .background(
                Capsule()
                    .fill(AppTheme.Colors.surfaceGhost(for: colorScheme))
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 0.5)
                    )
            )
    }

    private func summaryAccessibilityLabel(_ summary: WatchHistorySummary) -> String {
        var parts: [String] = []
        if summary.hasCompletedHistory { parts.append("Watched \(summary.completedCycleCount) times") }
        if summary.hasRewatchHistory { parts.append("Rewatched \(summary.completedRewatchCount) times") }
        if summary.activeRewatchCount > 0 { parts.append("Rewatch in progress") }
        if summary.pausedRewatchCount > 0 { parts.append("Rewatch paused") }
        if summary.archivedPartialRewatchCount > 0 { parts.append("Partial rewatch") }
        if parts.isEmpty { parts.append("Watch in progress") }
        return parts.joined(separator: ", ")
    }
}
