import SwiftUI
import Charts

/// Right section of the Taste Profile card — the rating donut chart plus
/// the personality label and colour legend to its right.
struct TasteRatingSection: View {
    let stats: LibraryStats

    private struct ChartSegment: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let color: Color
    }

    private var distribution: [(label: String, count: Int, color: Color, pct: Double)] {
        let total = max(stats.lovedCount + stats.likedCount + stats.dislikedCount + stats.unratedCount, 1)
        return [
            ("Loved",    stats.lovedCount,    .pink,             Double(stats.lovedCount)    / Double(total) * 100),
            ("Liked",    stats.likedCount,    .green,            Double(stats.likedCount)    / Double(total) * 100),
            ("Disliked", stats.dislikedCount, .red.opacity(0.85),Double(stats.dislikedCount) / Double(total) * 100),
            ("Unrated",  stats.unratedCount,  .gray.opacity(0.4),Double(stats.unratedCount)  / Double(total) * 100),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            if !stats.ratingPersonality.isEmpty {
                personalityHeader
            }

            HStack(alignment: .center, spacing: AppTheme.Spacing.large) {
                donutChart
                legend
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: – Personality header

    private var personalityHeader: some View {
        HStack(spacing: 7) {
            Text(personalityEmoji)
                .font(.system(size: 15))
            Text(stats.ratingPersonality.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(0.6)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private var personalityEmoji: String {
        switch stats.ratingPersonality {
        case "Hopeless Romantic": return "❤️"
        case "Harsh Critic":      return "🍿"
        case "Enthusiast":        return "✨"
        case "Mystery Critic":    return "❓"
        default:                  return "⚖️"
        }
    }

    // MARK: – Donut chart

    private var donutChart: some View {
        let chartSegments = distribution.map { ChartSegment(label: $0.label, value: Double($0.count), color: $0.color) }
        let topSegment    = distribution.max(by: { $0.pct < $1.pct })

        return ZStack {
            Chart(chartSegments) { seg in
                SectorMark(
                    angle: .value("Count", seg.value),
                    innerRadius: .ratio(0.64),
                    angularInset: 2.5
                )
                .foregroundStyle(seg.color.gradient)
                .cornerRadius(5)
            }
            .chartLegend(.hidden)
            .frame(width: 185, height: 185)
            .animation(AppTheme.Animation.chartReveal, value: distribution.map(\.count))

            if let top = topSegment {
                VStack(spacing: 0) {
                    Text(top.label.capitalized)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(Int(top.pct))%")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(top.color)
                }
                .frame(width: 80)
            }
        }
    }

    // MARK: – Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            ForEach(distribution.filter { $0.count > 0 }, id: \.label) { entry in
                HStack(spacing: AppTheme.Spacing.small) {
                    Circle()
                        .fill(entry.color)
                        .frame(width: 7, height: 7)
                    Text(entry.label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(entry.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.6))
                        .frame(minWidth: 24, alignment: .trailing)
                }
            }
        }
    }
}
