import SwiftUI

struct YourJourneyView: View {
    let history: [WatchTimePoint]
    let decades: [DecadeDistributionPoint]
    let favoriteEra: String?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.large) {
            // Left: Sparkline
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text("Activity Spark")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .kerning(1.0)

                if history.isEmpty {
                    CuteEmptyState(icon: "chart.line.uptrend.xyaxis", message: "Your journey starts here ✨", color: .teal)
                        .frame(height: 80)
                } else {
                    sparklineView
                        .frame(height: 80)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right: Decades
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text("Era Explorer")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .kerning(1.0)

                if decades.isEmpty {
                    CuteEmptyState(icon: "calendar.badge.clock", message: "No era data yet", color: .orange)
                        .frame(height: 80)
                } else {
                    MiniBarChart(
                        items: decades.map { (label: $0.decade, value: $0.count, color: eraColor(for: $0.decade)) },
                        maxValue: decades.map { $0.count }.max() ?? 1
                    )
                    .frame(height: 80)
                }

                if let era = favoriteEra {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .font(.system(size: 9))
                        Text("Favorite era: \(era)")
                            .font(AppTheme.Font.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
    }

    private var sparklineView: some View {
        let last30 = Array(history.suffix(30))
        let values = last30.map { Double($0.minutes) }
        let max = values.max() ?? 1
        let dates = last30.map { $0.date }

        return VStack(alignment: .leading, spacing: 4) {
            ZStack {
                // Filled area
                SparklineShape(data: values, maxValue: max)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.Colors.accent.opacity(0.2), AppTheme.Colors.accent.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 60)

                // Line
                SparklineShape(data: values, maxValue: max)
                    .stroke(AppTheme.Colors.accent, lineWidth: 2)
                    .frame(height: 60)
            }

            if dates.count >= 2 {
                HStack {
                    Text(dates.first!.formatted(.dateTime.month(.abbreviated).day()))
                        .font(AppTheme.Font.tiny)
                    Spacer()
                    Text(dates.last!.formatted(.dateTime.month(.abbreviated).day()))
                        .font(AppTheme.Font.tiny)
                }
                .foregroundStyle(.secondary.opacity(0.6))
            }
        }
    }

    private func eraColor(for decade: String) -> Color {
        let year = Int(decade.dropLast()) ?? 0
        if year < 1980 { return Color.brown }
        if year < 1990 { return Color.orange.opacity(0.7) }
        if year < 2000 { return Color.pink.opacity(0.7) }
        if year < 2010 { return Color.purple.opacity(0.7) }
        if year < 2020 { return Color.blue }
        return Color.teal
    }
}
