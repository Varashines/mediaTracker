import SwiftUI
import Charts

struct TasteDNAView: View {
    let stats: LibraryStats
    @Environment(\.colorScheme) var colorScheme

    private var totalRated: Int {
        stats.lovedCount + stats.likedCount + stats.dislikedCount
    }

    private var distribution: [(label: String, count: Int, color: Color, pct: Double)] {
        let total = max(totalRated + stats.unratedCount, 1)
        return [
            ("Loved",    stats.lovedCount,    .pink,              Double(stats.lovedCount)    / Double(total) * 100),
            ("Liked",    stats.likedCount,    .green,             Double(stats.likedCount)    / Double(total) * 100),
            ("Disliked", stats.dislikedCount, .red.opacity(0.7),  Double(stats.dislikedCount) / Double(total) * 100),
            ("Unrated",  stats.unratedCount,  .gray.opacity(0.5), Double(stats.unratedCount)  / Double(total) * 100),
        ]
    }

    private var personalityIcon: String {
        switch stats.ratingPersonality {
        case "Hopeless Romantic": return "heart.fill"
        case "Harsh Critic":      return "hand.thumbsdown.fill"
        case "Enthusiast":        return "sparkles"
        case "Mystery Critic":    return "questionmark.circle.fill"
        default:                  return "star.fill"
        }
    }

    private var personalityColor: Color {
        switch stats.ratingPersonality {
        case "Hopeless Romantic": return .pink
        case "Harsh Critic":      return .red
        case "Enthusiast":        return .orange
        case "Mystery Critic":    return .gray
        default:                  return .yellow
        }
    }

    var body: some View {
        GlassCard(color: personalityColor) {
            HStack(spacing: 0) {
                // Zone 1 — Personality Identity (left)
                personalityZone
                    .frame(maxWidth: .infinity)

                // Zone 2 — Donut Chart (center)
                donutZone
                    .frame(maxWidth: .infinity)

                // Zone 3 — Progress Bar Legend (right)
                legendZone
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, AppTheme.Spacing.medium)
            .padding(.horizontal, AppTheme.Spacing.medium)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Zone 1: Personality

    private var personalityZone: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            ZStack {
                Circle()
                    .fill(personalityColor.opacity(colorScheme == .dark ? 0.15 : 0.10))
                    .frame(width: 48, height: 48)
                Image(systemName: personalityIcon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(personalityColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Rating Style")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .kerning(AppTheme.Kerning.wide)

                Text(stats.ratingPersonality.isEmpty ? "—" : stats.ratingPersonality)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(totalRated)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(personalityColor)
                Text("RATED")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .kerning(AppTheme.Kerning.wide)
            }
        }
        .padding(.vertical, AppTheme.Spacing.small)
        .padding(.leading, AppTheme.Spacing.small)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Zone 2: Donut Chart

    private struct ChartSegment: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let color: Color
    }

    private var donutZone: some View {
        let chartSegments: [ChartSegment] = distribution.map {
            ChartSegment(label: $0.label, value: Double($0.count), color: $0.color)
        }

        return ZStack {
            Chart(chartSegments) { seg in
                SectorMark(
                    angle: .value("Count", seg.value),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.0
                )
                .foregroundStyle(seg.color)
                .cornerRadius(4)
            }
            .chartLegend(.hidden)
            .frame(width: 150, height: 150)
            .animation(AppTheme.Animation.chartReveal, value: distribution.map(\.count))

            VStack(spacing: 2) {
                Text(stats.ratingPersonality.isEmpty ? "—" : stats.ratingPersonality)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 70)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Zone 3: Progress Bar Legend

    private var legendZone: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            ForEach(distribution, id: \.label) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 6, height: 6)
                        Text(item.label)
                            .font(AppTheme.Font.bodyMedium)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(Int(item.pct))%")
                            .font(AppTheme.Font.monoCaption)
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(item.color.opacity(colorScheme == .dark ? 0.15 : 0.10))
                                .frame(height: 6)

                            Capsule()
                                .fill(item.color.opacity(0.85))
                                .frame(width: geo.size.width * CGFloat(item.pct / 100), height: 6)
                                .animation(AppTheme.Animation.chartReveal, value: item.pct)
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding(.vertical, AppTheme.Spacing.small)
        .padding(.trailing, AppTheme.Spacing.small)
        .frame(maxHeight: .infinity, alignment: .center)
    }
}
