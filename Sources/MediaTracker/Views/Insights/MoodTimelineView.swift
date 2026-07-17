import SwiftUI

struct MoodTimelineView: View {
    let stats: LibraryStats
    @Environment(\.colorScheme) var colorScheme
    @State private var animateBars = false
    @State private var ringAngle: Double = 0
    @State private var hoveredMood: Mood? = nil

    var body: some View {
        VStack(spacing: AppTheme.Spacing.compact) {
            if !stats.moodBreakdown.isEmpty {
                // Mood ring
                moodRing

                // Insight line
                insightSection

                // Bar chart
                moodBars
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text("Select ✦ Mood in any detail view to build your emotional map")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animateBars = true
            }
            withAnimation(.spring(response: 1.2, dampingFraction: 0.75)) {
                ringAngle = 360
            }
        }
    }

    // MARK: - Mood Ring

    @ViewBuilder
    private var moodRing: some View {
        let total = stats.moodBreakdown.reduce(0) { $0 + $1.count }

        if total > 0 {
            let topEntry = stats.moodBreakdown.max(by: { $0.percentage < $1.percentage })
            let topMood = topEntry.flatMap { Mood(rawValue: $0.name) }
            let topPct = topEntry?.percentage ?? 0

            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius: CGFloat = 52
                    var startAngle: Angle = .degrees(-90)

                    for entry in stats.moodBreakdown {
                        if let mood = Mood(rawValue: entry.name) {
                            let pct = entry.percentage / 100
                            let sweep = pct * ringAngle
                            if sweep > 0 {
                                let endAngle = startAngle + .degrees(sweep)
                                var path = Path()
                                path.addArc(center: center, radius: radius,
                                            startAngle: startAngle, endAngle: endAngle, clockwise: false)

                                let isTop = entry.name == topEntry?.name
                                let lineWidth: CGFloat = isTop ? 12 : 10

                                if isTop {
                                    context.stroke(path, with: .color(mood.color.opacity(0.3)),
                                                   style: StrokeStyle(lineWidth: 14, lineCap: .round))
                                }

                                context.stroke(path, with: .color(mood.color.opacity(0.75)),
                                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                                startAngle = endAngle
                            }
                        }
                    }

                    context.stroke(
                        Circle().path(in: CGRect(x: center.x - radius + 1, y: center.y - radius + 1,
                                                width: (radius - 1) * 2, height: (radius - 1) * 2)),
                        with: .color(Color.primary.opacity(0.04)),
                        style: StrokeStyle(lineWidth: 1)
                    )
                }
                .frame(width: 120, height: 120)

                if let mood = topMood {
                    VStack(spacing: 2) {
                        Image(systemName: mood.emoji)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(mood.color)
                        Text("\(Int(topPct))%")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Insight

    private var insightSection: some View {
        Group {
            if let top = stats.moodBreakdown.max(by: { $0.percentage < $1.percentage }),
               let topMood = Mood(rawValue: top.name) {
                let topPct = top.percentage
                HStack(spacing: 6) {
                    Image(systemName: topMood.emoji)
                        .font(.system(size: 13))
                        .foregroundStyle(topMood.color)
                    if topPct > 50 {
                        Text("\(top.name) dominates your emotional landscape")
                    } else if let second = stats.moodBreakdown
                        .sorted(by: { $0.percentage > $1.percentage })
                        .dropFirst().first,
                              let secondMood = Mood(rawValue: second.name),
                              topPct - second.percentage < 10 {
                        HStack(spacing: 4) {
                            Text("\(top.name) and ")
                            Image(systemName: secondMood.emoji)
                                .font(.system(size: 11))
                                .foregroundStyle(secondMood.color)
                            Text(second.name)
                        }
                    } else {
                        Text("Most felt: \(top.name) (\(Int(topPct))%)")
                    }
                }
                .font(AppTheme.Font.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(animateBars ? 1 : 0)
                .offset(y: animateBars ? 0 : -6)
                .animation(.easeOut(duration: 0.5).delay(0.3), value: animateBars)
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Bars

    private var moodBars: some View {
        VStack(spacing: 6) {
            ForEach(stats.moodBreakdown, id: \.name) { entry in
                if let mood = Mood(rawValue: entry.name) {
                    moodBarRow(mood: mood, percentage: entry.percentage)
                }
            }
        }
    }

    private func moodBarRow(mood: Mood, percentage: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: mood.emoji)
                .font(.system(size: 11))
                .foregroundStyle(mood.color)
                .frame(width: 18, alignment: .center)

            Text(mood.rawValue)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .frame(width: 40, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(mood.color.opacity(0.07))
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(mood.color.opacity(0.55))
                        .frame(width: geo.size.width * CGFloat(animateBars ? percentage / 100 : 0))
                }
            }
            .frame(height: 8)

            Text("\(Int(percentage))%")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }
}
