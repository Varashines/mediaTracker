import SwiftUI

struct SpectrumView: View {
    let items: [BarcodeSlice]
    @State private var hoveredItem: BarcodeSlice?
    @State private var isScanning = false
    @State private var scanPosition: CGFloat = 0.0
    @Environment(\.colorScheme) private var colorScheme
    private let validItems: [BarcodeSlice]
    private let bars: [SpectrumBar]

    private struct SpectrumBar: Identifiable {
        let item: BarcodeSlice
        let color: Color
        var id: String { item.id }
    }

    init(items: [BarcodeSlice]) {
        let validItems = items.filter {
            $0.themeColorHex != nil || $0.tasteValue != TasteValue.none.rawValue
        }
        self.items = items
        self.validItems = validItems
        self.bars = validItems.map {
            SpectrumBar(item: $0, color: Self.makeBarColor(for: $0))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.top, AppTheme.Spacing.medium)
                .padding(.bottom, AppTheme.Spacing.small)
            barcodeArea
                .padding(.bottom, AppTheme.Spacing.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .insightsCardSurface()
    }

    // MARK: – Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("CINEMA DNA")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundStyle(AppTheme.Colors.accent)
                Text("SIGNATURE")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.6))
            }

            Spacer()

            ZStack {
                if let item = hoveredItem {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(barColor(item))
                            .frame(width: 7, height: 7)
                        Text(item.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(item.tasteValue == TasteValue.none.rawValue ? "UNRATED" : item.tasteValue.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(barColor(item))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    Text(validItems.count > 0 && !AppThemeCoordinator.isReducingVisualEffects
                         ? "HOVER TO SCAN"
                         : "\(validItems.count) TITLES")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .transition(.opacity)
                }
            }
            .animation(AppTheme.Animation.adaptive(AppTheme.Animation.hoverFade), value: hoveredItem?.id)
        }
    }

    // MARK: – Barcode

    @ViewBuilder
    private var barcodeArea: some View {
        if validItems.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "barcode.viewfinder")
                    .font(AppTheme.Font.title3)
                    .foregroundStyle(AppTheme.Colors.accent.opacity(0.6))
                Text("Add titles to generate your spectrum")
                    .font(AppTheme.Font.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        } else {
            ZStack {
                HStack(spacing: 1.5) {
                    Spacer(minLength: 0)
                    ForEach(bars.prefix(160)) { bar in
                        let isHov = hoveredItem?.id == bar.id
                        Rectangle()
                            .fill(isHov ? bar.color : bar.color.opacity(0.8))
                            .frame(height: isHov ? 62 : 46)
                            .frame(minWidth: 1.5, maxWidth: 3.5)
                            .animation(AppTheme.Animation.adaptive(AppTheme.Animation.hoverFade), value: isHov)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                AppTheme.Animation.with(AppTheme.Animation.hoverFade) {
                                    hoveredItem = hovering ? bar.item : nil
                                    if hovering { isScanning = true }
                                    else if hoveredItem == nil { isScanning = false }
                                }
                            }
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 68)
                // Fade edges
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.05),
                            .init(color: .black, location: 0.95),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                // Scanning laser
                if isScanning, !AppThemeCoordinator.isReducingVisualEffects {
                    GeometryReader { geo in
                        AppTheme.Colors.accent.opacity(0.5)
                            .frame(width: 1.5, height: 68)
                            .shadow(color: AppTheme.Colors.accent.opacity(0.9), radius: 8, x: 0, y: 0)
                            .offset(x: scanPosition * geo.size.width)
                            .onAppear {
                                scanPosition = 0
                                AppTheme.Animation.with(AppTheme.Animation.pulseLoop) {
                                    scanPosition = 1.0
                                }
                            }
                            .onDisappear { scanPosition = 0 }
                    }
                    .allowsHitTesting(false)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cinema DNA spectrum, \(validItems.count) titles visualized")
        }
    }

    private static func makeBarColor(for item: BarcodeSlice) -> Color {
        if let hex = item.themeColorHex, let color = Color(hex: hex) {
            return color
        }
        guard let taste = TasteValue(rawValue: item.tasteValue) else { return .gray }
        return taste.color
    }

    private func barColor(_ item: BarcodeSlice) -> Color {
        bars.first(where: { $0.id == item.id })?.color ?? Self.makeBarColor(for: item)
    }
}
