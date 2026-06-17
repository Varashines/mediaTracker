import SwiftUI
import Charts

struct TasteDNAView: View {
    let stats: LibraryStats
    @Environment(\.colorScheme) var colorScheme

    private struct Segment: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let color: Color
    }

    private var segments: [Segment] {
        let totalRated = stats.lovedCount + stats.likedCount + stats.dislikedCount
        let total = totalRated + stats.unratedCount
        guard total > 0 else { return [] }
        return [
            Segment(label: "Loved", value: Double(stats.lovedCount), color: .pink),
            Segment(label: "Liked", value: Double(stats.likedCount), color: .green),
            Segment(label: "Disliked", value: Double(stats.dislikedCount), color: .red.opacity(0.6)),
            Segment(label: "Unrated", value: Double(stats.unratedCount), color: .gray.opacity(0.4)),
        ]
    }

    private var totalRated: Int {
        stats.lovedCount + stats.likedCount + stats.dislikedCount
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.large) {
            // Donut Chart
            ZStack {
                Chart(segments) { seg in
                    SectorMark(
                        angle: .value("Count", seg.value),
                        innerRadius: .ratio(0.55),
                        angularInset: 1.5
                    )
                    .foregroundStyle(seg.color)
                    .cornerRadius(4)
                }
                .chartLegend(.hidden)
                .frame(width: 130, height: 130)

                // Center label
                VStack(spacing: 2) {
                    Text("\(totalRated)")
                        .font(AppTheme.Font.titleLarge)
                    Text("Rated")
                        .font(AppTheme.Font.label)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                if !stats.ratingPersonality.isEmpty {
                    PersonalityBadge(personality: stats.ratingPersonality)
                }

                ForEach(segments) { seg in
                    let pct = totalRated > 0 ? seg.value / Double(totalRated + stats.unratedCount) : 0
                    tasteLegend(color: seg.color, label: seg.label, count: Int(seg.value), pct: pct)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
    }

    func tasteLegend(color: Color, label: String, count: Int, pct: Double) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(AppTheme.Font.bodyMedium)
                .foregroundStyle(.primary)
                .frame(width: 60, alignment: .leading)
            Text("\(count)")
                .font(AppTheme.Font.heading)
                .foregroundStyle(color)
            Text(String(format: "(%.0f%%)", pct * 100))
                .font(AppTheme.Font.label)
                .foregroundStyle(.secondary)
        }
    }
}
