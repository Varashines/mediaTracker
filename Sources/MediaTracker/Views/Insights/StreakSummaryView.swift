import SwiftUI

struct StreakSummaryView: View {
    let stats: LibraryStats
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        InsightGlassTile {
            VStack(spacing: AppTheme.Spacing.small) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.orange)
                        .shadow(color: .orange.opacity(0.3), radius: 4)
                    Text("\(stats.currentStreak)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                        .contentTransition(.numericText())
                    Text(stats.currentStreak == 1 ? "day" : "days")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Text(streakMessage)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 4) {
                    Text("Longest")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.tertiary)
                    Text("\(stats.longestStreak)")
                        .font(AppTheme.Font.bodyMedium)
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    if stats.totalEpisodesWatched > 0 {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("Today")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.tertiary)
                        Text("\(stats.totalEpisodesWatched)")
                            .font(AppTheme.Font.bodyMedium)
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        Text("ep")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, AppTheme.Spacing.small)
        }
    }

    private var streakMessage: String {
        let current = stats.currentStreak
        if current >= 30 { return "Blazing hot — \(current) day streak!" }
        if current >= 14 { return "Two weeks strong! Unstoppable" }
        if current >= 7 { return "On fire — a full week of watching" }
        if current >= 3 { return "Building rhythm — \(current) days and counting" }
        if current > 0 { return "\(current) day streak — keep it going" }
        return "Watch something today to start a streak"
    }
}
