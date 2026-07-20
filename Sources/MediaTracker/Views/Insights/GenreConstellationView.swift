import SwiftUI

// MARK: - Genre Color Palette

private func genreColor(_ name: String) -> Color {
    let lower = name.lowercased()
    if lower.contains("action") || lower.contains("adventure") { return .orange }
    if lower.contains("comedy") { return .yellow }
    if lower.contains("drama") { return .blue }
    if lower.contains("horror") || lower.contains("thriller") { return .red }
    if lower.contains("romance") { return .pink }
    if lower.contains("sci-fi") || lower.contains("science") { return .cyan }
    if lower.contains("fantasy") || lower.contains("animation") { return .purple }
    if lower.contains("crime") || lower.contains("mystery") { return .indigo }
    if lower.contains("documentary") || lower.contains("history") { return .brown }
    if lower.contains("family") { return .green }
    if lower.contains("music") || lower.contains("musical") { return .mint }
    return .teal
}

// MARK: - Genre Constellation View

struct GenreConstellationView: View {
    let items: [(name: String, percentage: Double)]

    var body: some View {
        if items.isEmpty {
            CuteEmptyState(icon: "sparkles.magnifyingglass", message: "Discover more genres!", color: .indigo)
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
        } else {
            GenreBubbleChart(items: Array(items.prefix(5)))
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
        }
    }
}

// MARK: - Bubble Chart Layout

private struct GenreBubbleChart: View {
    let items: [(name: String, percentage: Double)]
    @Environment(\.colorScheme) var colorScheme

    private var normalized: [(name: String, pct: Double, weight: Double, color: Color)] {
        let maxPct = items.map(\.percentage).max() ?? 1.0
        return items.map { item in
            (
                name: item.name,
                pct: item.percentage,
                weight: item.percentage / maxPct,
                color: genreColor(item.name)
            )
        }
    }

    private let minDiam: CGFloat = 65
    private let maxDiam: CGFloat = 110

    private func diameter(for weight: Double) -> CGFloat {
        minDiam + CGFloat(weight) * (maxDiam - minDiam)
    }

    var body: some View {
        let items = normalized
        let row1 = Array(items.prefix(2))
        let row2 = items.count > 2 ? Array(items[2..<min(5, items.count)]) : []

        VStack(spacing: AppTheme.Spacing.small) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.small) {
                ForEach(Array(row1.enumerated()), id: \.offset) { idx, item in
                    GenreBubble(
                        rank: idx + 1,
                        name: item.name,
                        percentage: item.pct,
                        color: item.color,
                        diameter: diameter(for: item.weight),
                        colorScheme: colorScheme
                    )
                }
            }
            .frame(maxWidth: .infinity)

            if !row2.isEmpty {
                HStack(alignment: .center, spacing: AppTheme.Spacing.small) {
                    ForEach(Array(row2.enumerated()), id: \.offset) { idx, item in
                        GenreBubble(
                            rank: idx + 3,
                            name: item.name,
                            percentage: item.pct,
                            color: item.color,
                            diameter: diameter(for: item.weight),
                            colorScheme: colorScheme
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Single Bubble

private struct GenreBubble: View {
    let rank: Int
    let name: String
    let percentage: Double
    let color: Color
    let diameter: CGFloat
    let colorScheme: ColorScheme

    @State private var isHovered = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            color.opacity(colorScheme == .dark ? 0.28 : 0.18),
                            color.opacity(colorScheme == .dark ? 0.10 : 0.07)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: diameter
                    )
                )

            Circle()
                .stroke(
                    color.opacity(colorScheme == .dark ? 0.35 : 0.22),
                    lineWidth: isHovered ? 1.5 : 1.0
                )

            VStack(spacing: 2) {
                Text("#\(rank)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(color.opacity(0.7))

                Text(name)
                    .font(.system(size: clampedFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(String(format: "%.0f%%", percentage * 100))
                    .font(.system(size: max(9, clampedFontSize - 1), weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            }
            .padding(AppTheme.Spacing.tiny)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(isHovered ? 1.05 : (appeared ? 1.0 : 0.6))
        .opacity(appeared ? 1 : 0)
        .shadow(
            color: color.opacity(isHovered ? (colorScheme == .dark ? 0.35 : 0.20) : 0),
            radius: 12, y: 4
        )
        .animation(
            AppTheme.Animation.springGentle.delay(Double(rank - 1) * 0.06),
            value: appeared
        )
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onAppear {
            appeared = true
        }
        .onHover { hovering in
            withAnimation(AppTheme.Animation.springSnappy) {
                isHovered = hovering
            }
        }
        .help("\(name): \(String(format: "%.0f%%", percentage * 100)) of your library")
    }

    private var clampedFontSize: CGFloat {
        if diameter >= 100 { return 11 }
        return 9
    }
}
