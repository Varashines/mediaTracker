import SwiftData
import SwiftUI

/// Per-occurrence watch log for a title: one row per pass, with the dates and
/// runtime the `WatchEvent` ledger recorded. The summary pills above it only
/// carry counts, so this is the surface that answers "when did I watch this?".
struct WatchLogView: View {
    let mediaID: String
    let firstWatchedAt: Date?
    let themeColor: Color

    @Query private var cycles: [WatchCycle]
    @Query private var events: [WatchEvent]
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false

    private var passes: [WatchLogPass] {
        WatchLogBuilder.passes(cycles: cycles, events: events)
    }

    var body: some View {
        if !passes.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                header
                .help(isExpanded ? "Hide watch history" : "Show watch history")
                .accessibilityLabel("Watch History, \(passes.count) passes")
                .accessibilityHint(isExpanded ? "Collapses the watch history" : "Expands the watch history")

                Text(WatchLogBuilder.summary(passes: passes, firstWatchedAt: firstWatchedAt))
                    .font(AppTheme.Font.tiny)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isExpanded {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.mini) {
                        ForEach(passes) { pass in
                            passRow(pass)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, AppTheme.Spacing.tiny)
            .padding(.horizontal, AppTheme.Spacing.small)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(AppTheme.Colors.surfaceGhost(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                            .stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 0.5)
                    )
            }
        }
    }

    private var header: some View {
        Button {
            AppTheme.Animation.with(AppTheme.Animation.microInteraction) { isExpanded.toggle() }
        } label: {
            headerContent
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Hide watch history" : "Show watch history")
        .accessibilityLabel("Watch History, \(passes.count) passes")
        .accessibilityHint(isExpanded ? "Collapses the watch history" : "Expands the watch history")
    }

    private var headerContent: some View {
        HStack(spacing: AppTheme.Spacing.mini) {
            Image(systemName: "clock.arrow.circlepath")
                .font(AppTheme.Font.caption2)
                .foregroundStyle(accent)
            Text("Watch History")
                .font(AppTheme.Font.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.85))
            Image(systemName: "chevron.right")
                .font(AppTheme.Font.tiny)
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
            Spacer(minLength: 0)
            Text("\(passes.count)")
                .font(AppTheme.Font.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }

    private var accent: Color {
        themeColor.highContrastAccent(colorScheme: colorScheme)
    }

    private func passRow(_ pass: WatchLogPass) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.mini) {
            Image(systemName: pass.stateIcon)
                .font(AppTheme.Font.tiny)
                .foregroundStyle(pass.isFinished ? accent : .secondary)
                .frame(width: 14)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: AppTheme.Spacing.mini) {
                    Text(pass.title)
                        .font(AppTheme.Font.tiny.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.85))
                    Text(pass.stateDescription)
                        .font(AppTheme.Font.tiny)
                        .foregroundStyle(.secondary)
                    if pass.isBackfilled {
                        Text("estimated")
                            .font(AppTheme.Font.tiny)
                            .foregroundStyle(.tertiary)
                            .help("These dates were reconstructed from your library rather than recorded as you watched.")
                    }
                }

                if let range = pass.dateRangeDescription {
                    Text(range)
                        .font(AppTheme.Font.tiny)
                        .foregroundStyle(.secondary)
                }

                let detail = detailText(for: pass)
                if !detail.isEmpty {
                    Text(detail)
                        .font(AppTheme.Font.tiny)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: pass))
    }

    private func detailText(for pass: WatchLogPass) -> String {
        var parts: [String] = []
        if pass.occurrenceCount > 0 {
            parts.append(pass.occurrenceCount == 1 ? "1 episode" : "\(pass.occurrenceCount) episodes")
        }
        if pass.runtimeMinutes > 0 {
            parts.append(DateUtils.formatRuntime(pass.runtimeMinutes))
        }
        return parts.joined(separator: " · ")
    }

    private func accessibilityLabel(for pass: WatchLogPass) -> String {
        var parts = [pass.title, pass.stateDescription]
        if let range = pass.dateRangeDescription { parts.append(range) }
        let detail = detailText(for: pass)
        if !detail.isEmpty { parts.append(detail) }
        return parts.joined(separator: ", ")
    }
}
