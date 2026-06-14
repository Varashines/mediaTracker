import SwiftUI

struct RatingDonutChart: View {
    let loved: Int
    let liked: Int
    let disliked: Int
    let unrated: Int

    private var total: Int { loved + liked + disliked + unrated }
    private var hasData: Bool { total > 0 }

    private struct ComputedSegment: Identifiable {
        let id: Int
        let start: Double
        let end: Double
        let color: Color
        let label: String
        let value: Int
    }

    private var computedSegments: [ComputedSegment] {
        let raw = [
            (loved, Color.red, "Love"),
            (liked, Color.blue, "Like"),
            (unrated, Color.gray.opacity(0.35), "Unrated"),
            (disliked, Color.orange, "Dislike")
        ]

        var currentSum = 0.0
        var list: [ComputedSegment] = []
        for (index, item) in raw.enumerated() {
            guard item.0 > 0 else { continue }
            let fraction = Double(item.0) / Double(max(1, total))
            list.append(ComputedSegment(
                id: index,
                start: currentSum,
                end: currentSum + fraction,
                color: item.1,
                label: item.2,
                value: item.0
            ))
            currentSum += fraction
        }
        return list
    }

    var body: some View {
        DashboardCard {
            HStack(spacing: AppTheme.Spacing.xLarge) {
                ZStack {
                    if hasData {
                        let arcWidth: CGFloat = 22
                        ForEach(computedSegments) { seg in
                            DonutArc(start: seg.start, end: seg.end, color: seg.color, lineWidth: arcWidth)
                        }
                    } else {
                        Circle()
                            .stroke(Color.primary.opacity(0.06), lineWidth: 22)
                    }

                    VStack(spacing: 2) {
                        Text("\(total)")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("TOTAL\nRATED")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 150, height: 150)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(computedSegments) { seg in
                        HStack(spacing: AppTheme.Spacing.small) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(seg.color)
                                .frame(width: 12, height: 12)

                            Text(seg.label)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .frame(width: 60, alignment: .leading)

                            Text("\(seg.value)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(String(format: "%.0f%%", (seg.end - seg.start) * 100))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct DonutArc: View {
    let start: Double
    let end: Double
    let color: Color
    let lineWidth: CGFloat

    @State private var animatedEnd: Double = 0.0

    var body: some View {
        Circle()
            .trim(from: start, to: animatedEnd)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    animatedEnd = end
                }
            }
            .onChange(of: end) { _, newValue in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    animatedEnd = newValue
                }
            }
    }
}
