import SwiftUI

struct StreakSummaryView: View {
    let stats: LibraryStats
    @Environment(\.colorScheme) var colorScheme

    private let calendar = Calendar.current
    private let totalWeeks = 16
    private let cellSize: CGFloat = 10
    private let cellSpacing: CGFloat = 2

    var body: some View {
        InsightGlassTile {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                // Calendar heatmap
                heatmapGrid

                // Stats row
                HStack(spacing: 0) {
                    statsItem(value: "\(stats.longestStreak)", label: "Longest")
                    Divider().frame(height: 28)
                    statsItem(value: streakWeeksLabel, label: "Best streak")
                    Divider().frame(height: 28)
                    statsItem(value: "\(stats.totalEpisodesWatched)", label: "Episodes")
                }

                // Message
                if stats.currentStreak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text(streakMessage)
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Watch something today to start a new streak")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var streakMessage: String {
        let current = stats.currentStreak
        if current >= 30 { return "Blazing hot — \(current) day streak!" }
        if current >= 14 { return "Two weeks strong! Your dedication 🔥" }
        if current >= 7 { return "A full week on fire — keep rolling" }
        if current >= 3 { return "\(current) days and building momentum" }
        return "\(current) day streak — keep it up"
    }

    private var streakWeeksLabel: String {
        guard stats.longestStreak > 0 else { return "0" }
        if stats.longestStreak < 7 { return "\(stats.longestStreak)d" }
        let weeks = (stats.longestStreak + 6) / 7
        return "\(weeks)w"
    }

    private func statsItem(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Text(label)
                .font(AppTheme.Font.tiny)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Heatmap

    private var heatmapGrid: some View {
        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -(totalWeeks * 7 - 1), to: today)!

        return VStack(alignment: .leading, spacing: cellSpacing) {
            // Month headers
            HStack(spacing: cellSpacing) {
                ForEach(monthLabels(from: startDate, to: today), id: \.offset) { month in
                    Text(month.label)
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: CGFloat(month.span) * (cellSize + cellSpacing), alignment: .leading)
                }
            }
            .padding(.leading, 14)

            // Day rows
            HStack(spacing: cellSpacing) {
                // Day labels
                VStack(spacing: cellSpacing) {
                    ForEach(["M", "W", "F"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 7))
                            .foregroundStyle(.tertiary)
                            .frame(height: cellSize)
                    }
                }

                // Grid columns (one per week)
                HStack(spacing: cellSpacing) {
                    ForEach(0..<totalWeeks, id: \.self) { weekIndex in
                        VStack(spacing: cellSpacing) {
                            ForEach(0..<7, id: \.self) { dayIndex in
                                let date = calendar.date(byAdding: .day,
                                    value: weekIndex * 7 + dayIndex,
                                    to: startDate)!
                                let isActive = stats.watchDaysLast16Weeks.contains(date)
                                let isToday = calendar.isDate(date, inSameDayAs: today)

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(cellColor(isActive: isActive, isToday: isToday))
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
            }
        }
    }

    private func cellColor(isActive: Bool, isToday: Bool) -> Color {
        if isToday {
            return .orange.opacity(0.7)
        }
        if isActive {
            return colorScheme == .dark ? .orange.opacity(0.5) : .orange.opacity(0.35)
        }
        return colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    private func monthLabels(from start: Date, to end: Date) -> [(offset: Int, label: String, span: Int)] {
        var current = start
        var labels: [(offset: Int, label: String, span: Int)] = []
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM"

        while current <= end {
            let monthName = fmt.string(from: current)
            let daysInMonth = calendar.range(of: .day, in: .month, for: current)?.count ?? 30
            let weeksSpan = (daysInMonth + 6) / 7
            labels.append((labels.count, monthName, weeksSpan))
            current = calendar.date(byAdding: .month, value: 1, to: current)!
        }
        return labels
    }
}
