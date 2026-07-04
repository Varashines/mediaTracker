import SwiftUI
import Charts

private func formatRuntime(_ minutes: Int) -> String {
    let hours = minutes / 60
    let mins = minutes % 60
    if hours > 0 { return "\(hours)h \(mins)m" }
    return "\(mins)m"
}

struct ProviderRingView: View {
    let providers: [(name: String, count: Int, percentage: Double, runtime: Int)]
    let providerCoverage: Double

    @State private var hoveredIndex: Int?
    @State private var selectedIndex: Int?
    @State private var isVisible = false

    private var displayProviders: [(name: String, count: Int, percentage: Double, runtime: Int)] {
        Array(providers.prefix(8))
    }

    private static let palette: [Color] = [
        .red, .blue, .green, .orange, .purple, .teal, .pink, .cyan
    ]

    private var coloredProviders: [(id: Int, name: String, percentage: Double, runtime: Int, color: Color)] {
        displayProviders.enumerated().map { i, p in
            (i, p.name, p.percentage, p.runtime, Self.palette[i % Self.palette.count])
        }
    }

    var body: some View {
        DashboardCard {
            if providers.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: AppTheme.Spacing.xLarge) {
                    ringSection
                    infoPanel
                }
                .padding(AppTheme.Spacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tv.and.mediabox")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No provider data yet")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 40)
    }

    private var ringSection: some View {
        ZStack {
            Chart(coloredProviders, id: \.id) { seg in
                SectorMark(
                    angle: .value("Share", seg.percentage),
                    innerRadius: .ratio(0.6),
                    angularInset: 2
                )
                .foregroundStyle(seg.color.opacity(
                    hoveredIndex == nil && selectedIndex == nil ? 1.0 :
                        (seg.id == (hoveredIndex ?? selectedIndex) ? 1.0 : 0.3)
                ))
                .cornerRadius(4)
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let plotAnchor = proxy.plotFrame else { return }
                                let plotFrame = geo[plotAnchor]
                                let center = CGPoint(x: plotFrame.midX, y: plotFrame.midY)
                                let dx = location.x - center.x
                                let dy = location.y - center.y
                                let dist = sqrt(dx * dx + dy * dy)
                                let outerRadius = min(plotFrame.width, plotFrame.height) / 2
                                let innerRadius = outerRadius * 0.6

                                guard dist >= innerRadius, dist <= outerRadius else {
                                    if selectedIndex == nil { hoveredIndex = nil }
                                    return
                                }

                                var angle = atan2(dy, dx) * 180 / .pi
                                if angle < 0 { angle += 360 }

                                let total = coloredProviders.reduce(0) { $0 + $1.percentage }
                                var startAngle: Double = 270
                                for seg in coloredProviders {
                                    let sweep = total > 0 ? seg.percentage / total * 360 : 0
                                    let endAngle = startAngle + sweep
                                    let inSegment: Bool
                                    if endAngle <= 360 {
                                        inSegment = angle >= startAngle && angle < endAngle
                                    } else {
                                        inSegment = angle >= startAngle || angle < endAngle - 360
                                    }
                                    if inSegment, sweep > 0 {
                                        hoveredIndex = seg.id
                                        return
                                    }
                                    startAngle = endAngle
                                }
                                if selectedIndex == nil { hoveredIndex = nil }

                            case .ended:
                                if selectedIndex == nil { hoveredIndex = nil }
                            }
                        }
                }
            }
            .frame(width: 260, height: 260)

            centerContent
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.85)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
    }

    @ViewBuilder
    private var centerContent: some View {
        let activeIdx = hoveredIndex ?? selectedIndex

        if let idx = activeIdx, idx < displayProviders.count {
            let p = displayProviders[idx]
            VStack(spacing: 2) {
                Text(p.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(String(format: "%.0f%%", p.percentage))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text("\(p.count) \(p.count == 1 ? "title" : "titles")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if p.runtime > 0 {
                    Text(formatRuntime(p.runtime))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .transition(.asymmetric(
                insertion: .scale(scale: 0.85).combined(with: .opacity),
                removal: .opacity
            ))
        } else if !coloredProviders.isEmpty {
            VStack(spacing: 2) {
                Text("\(coloredProviders.count)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text("PROVIDERS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .transition(.asymmetric(
                insertion: .opacity,
                removal: .scale(scale: 0.85).combined(with: .opacity)
            ))
        }
    }

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text("Provider Coverage")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", providerCoverage * 100))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 6) {
                ForEach(coloredProviders, id: \.id) { seg in
                    let isActive = seg.id == hoveredIndex || seg.id == selectedIndex

                    HStack(spacing: 8) {
                        Circle()
                            .fill(seg.color)
                            .frame(width: 7, height: 7)

                        Text(seg.name)
                            .font(.caption.weight(isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? .primary : .secondary)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Text(String(format: "%.0f%%", seg.percentage))
                            .font(.caption.monospacedDigit().weight(isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? .primary : .tertiary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isActive ? seg.color.opacity(0.1) : .clear)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onHover { hovering in
                        if hovering { hoveredIndex = seg.id }
                        else if hoveredIndex == seg.id { hoveredIndex = nil }
                    }
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if selectedIndex == seg.id { selectedIndex = nil }
                            else { selectedIndex = seg.id }
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
