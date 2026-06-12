import SwiftUI

struct TasteDNAView: View {
    let stats: LibraryStats
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let totalRated = stats.lovedCount + stats.likedCount + stats.dislikedCount
        let total = totalRated + stats.unratedCount
        let lovedPct = total > 0 ? Double(stats.lovedCount) / Double(total) : 0
        let likedPct = total > 0 ? Double(stats.likedCount) / Double(total) : 0
        let dislikedPct = total > 0 ? Double(stats.dislikedCount) / Double(total) : 0
        let unratedPct = total > 0 ? Double(stats.unratedCount) / Double(total) : 0

        HStack(spacing: AppTheme.Spacing.large) {
            // Donut
            ZStack {
                DonutSegment(startAngle: -90, endAngle: -90 + lovedPct * 360)
                    .fill(.pink)
                DonutSegment(startAngle: -90 + lovedPct * 360, endAngle: -90 + (lovedPct + likedPct) * 360)
                    .fill(.green)
                DonutSegment(startAngle: -90 + (lovedPct + likedPct) * 360, endAngle: -90 + (lovedPct + likedPct + dislikedPct) * 360)
                    .fill(.red.opacity(0.6))
                DonutSegment(startAngle: -90 + (lovedPct + likedPct + dislikedPct) * 360, endAngle: -90 + 360)
                    .fill(.gray.opacity(0.3))
            }
            .frame(width: 130, height: 130)
            .overlay {
                VStack(spacing: 2) {
                    Text("\(totalRated)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Rated")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                if !stats.ratingPersonality.isEmpty {
                    PersonalityBadge(personality: stats.ratingPersonality)
                }

                tasteLegend(color: .pink, label: "Loved", count: stats.lovedCount, pct: lovedPct)
                tasteLegend(color: .green, label: "Liked", count: stats.likedCount, pct: likedPct)
                tasteLegend(color: .red.opacity(0.6), label: "Disliked", count: stats.dislikedCount, pct: dislikedPct)
                tasteLegend(color: .gray.opacity(0.4), label: "Unrated", count: stats.unratedCount, pct: unratedPct)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
    }

    func tasteLegend(color: Color, label: String, count: Int, pct: Double) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 60, alignment: .leading)
            Text("\(count)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(String(format: "(%.0f%%)", pct * 100))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct DonutSegment: Shape {
    let startAngle: Double
    let endAngle: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let innerRadius = radius * 0.55
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(startAngle), endAngle: .degrees(endAngle), clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: .degrees(endAngle), endAngle: .degrees(startAngle), clockwise: true)
        path.closeSubpath()
        return path
    }
}
