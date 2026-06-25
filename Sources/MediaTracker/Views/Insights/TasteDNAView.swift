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
                        innerRadius: .ratio(0.58),
                        angularInset: 1.5
                    )
                    .foregroundStyle(seg.color)
                    .cornerRadius(4)
                }
                .chartLegend(.hidden)
                .frame(width: 150, height: 150)
                .animation(AppTheme.Animation.chartReveal, value: segments.map(\.value))

                // Center label
                VStack(spacing: 0) {
                    Text("\(totalRated)")
                        .font(AppTheme.Font.largeTitle)
                        .foregroundStyle(.primary)
                    Text("RATED")
                        .font(AppTheme.Font.caption2)
                        .kerning(AppTheme.Kerning.wide)
                        .foregroundStyle(.secondary)
                }

                if !stats.ratingPersonality.isEmpty {
                    PersonalityBadge(personality: stats.ratingPersonality)
                        .offset(y: 90)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(segments) { seg in
                    tasteLegend(color: seg.color, label: seg.label, count: Int(seg.value))
                }
            }
        }
        .padding(.vertical, AppTheme.Spacing.small)
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
    }

    func tasteLegend(color: Color, label: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(AppTheme.Font.bodyMedium)
                .foregroundStyle(.primary)
                .frame(width: 60, alignment: .leading)
            CountUpText(value: "\(count)")
                .font(AppTheme.Font.title3)
                .foregroundStyle(color)
        }
    }
}
