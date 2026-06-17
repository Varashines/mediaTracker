import SwiftUI
import Charts

struct RatingDonutChart: View {
    let loved: Int
    let liked: Int
    let disliked: Int
    let unrated: Int

    private var total: Int { loved + liked + disliked + unrated }
    private var hasData: Bool { total > 0 }

    private struct Segment: Identifiable {
        let id = UUID()
        let label: String
        let value: Int
        let color: Color
    }

    private var segments: [Segment] {
        [
            Segment(label: "Love", value: loved, color: .red),
            Segment(label: "Like", value: liked, color: .blue),
            Segment(label: "Unrated", value: unrated, color: .gray.opacity(0.35)),
            Segment(label: "Dislike", value: disliked, color: .orange),
        ]
        .filter { $0.value > 0 }
    }

    var body: some View {
        DashboardCard {
            HStack(spacing: AppTheme.Spacing.xLarge) {
                ZStack {
                    if hasData {
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
                        .animation(AppTheme.Animation.springGentle, value: total)
                    } else {
                        Circle()
                            .stroke(Color.primary.opacity(0.06), lineWidth: 22)
                    }

                    VStack(spacing: 2) {
                        Text("\(total)")
                            .font(AppTheme.Font.monoLarge)
                            .foregroundStyle(.primary)
                        Text("TOTAL\nRATED")
                            .font(AppTheme.Font.mono)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 150, height: 150)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(segments) { seg in
                        HStack(spacing: AppTheme.Spacing.small) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(seg.color)
                                .frame(width: 12, height: 12)

                            Text(seg.label)
                                .font(AppTheme.Font.bodyBold)
                                .foregroundStyle(.primary)
                                .frame(width: 60, alignment: .leading)

                            Text("\(seg.value)")
                                .font(AppTheme.Font.monoBody)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(String(format: "%.0f%%", total > 0 ? Double(seg.value) / Double(total) * 100 : 0))
                                .font(AppTheme.Font.monoCaption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating breakdown: \(loved) loved, \(liked) liked, \(disliked) disliked, \(unrated) unrated, \(total) total")
    }
}
