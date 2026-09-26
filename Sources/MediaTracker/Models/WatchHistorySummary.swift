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
    let themeColor: Color
    @Environment(\.colorScheme) private var colorScheme

    init(mediaID: String, themeColor: Color) {
        _cycles = Query(
            filter: #Predicate<WatchCycle> { cycle in
                cycle.mediaID == mediaID
            },
            sort: [SortDescriptor(\WatchCycle.startedAt, order: .reverse)]
        )
        self.themeColor = themeColor
    }

    private var accent: Color {
        themeColor.highContrastAccent(colorScheme: colorScheme)
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
        // Only counts live here. "Re-watching" / "In progress" are already stated
        // by the status capsule above, so repeating them was saying the same thing
        // twice in two visual languages. A partial rewatch is kept because the
        // capsule cannot express it — the title reads as Completed.
        if summary.hasRewatchHistory {
            summaryPill(
                icon: "arrow.trianglehead.2.clockwise.rotate.90",
                text: summary.completedRewatchCount == 1 ? "Rewatched once" : "Rewatched ×\(summary.completedRewatchCount)",
                isRewatch: true
            )
        }
        if summary.archivedPartialRewatchCount > 0 {
            summaryPill(icon: "minus.circle.fill", text: "Partial rewatch", isRewatch: true)
        }
    }

    /// `isRewatch` pills are outlined rather than filled. The accent colour is
    /// derived from the poster, so a filled accent made the status read as an
    /// error on a red poster and as a different arbitrary hue on every title —
    /// a status should not inherit an arbitrary palette.
    private func summaryPill(icon: String, text: String, isRewatch: Bool = false) -> some View {
        Label(text, systemImage: icon)
            .font(AppTheme.Font.caption2.weight(.semibold))
            .foregroundStyle(isRewatch ? accent : .primary.opacity(0.75))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, AppTheme.Spacing.small)
            .padding(.vertical, AppTheme.Spacing.micro)
            .background {
                Capsule()
                    .fill(AppTheme.Colors.surfaceGhost(for: colorScheme))
                    .overlay(
                        Capsule()
                            .stroke(
                                isRewatch ? accent.opacity(0.55) : AppTheme.Colors.strokeDefault(for: colorScheme),
                                lineWidth: isRewatch ? 1 : 0.5
                            )
                    )
            }
    }

    private func summaryAccessibilityLabel(_ summary: WatchHistorySummary) -> String {
        var parts: [String] = []
        if summary.hasCompletedHistory { parts.append("Watched \(summary.completedCycleCount) times") }
        if summary.hasRewatchHistory { parts.append("Rewatched \(summary.completedRewatchCount) times") }
        if summary.archivedPartialRewatchCount > 0 { parts.append("Partial rewatch") }
        if parts.isEmpty { parts.append("Not watched yet") }
        return parts.joined(separator: ", ")
    }
}
