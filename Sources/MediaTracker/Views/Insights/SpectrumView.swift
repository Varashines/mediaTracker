import SwiftUI

struct SpectrumView: View {
    let items: [BarcodeSlice]
    @State private var hoveredItem: BarcodeSlice?
    @State private var isScanning = false
    @State private var scanPosition: CGFloat = 0.0
    @Environment(\.colorScheme) private var colorScheme

    private var validItems: [BarcodeSlice] {
        items.filter { $0.themeColorHex != nil || $0.tasteValue != TasteValue.none.rawValue }
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
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .fill(AppTheme.Colors.accent.opacity(colorScheme == .dark ? 0.07 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(AppTheme.Colors.accent.opacity(0.16), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
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
            .animation(.easeInOut(duration: 0.15), value: hoveredItem?.id)
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
                    ForEach(Array(validItems.prefix(160).enumerated()), id: \.element.id) { _, item in
                        let isHov = hoveredItem?.id == item.id
                        let barColor = barColor(item)
                        Rectangle()
                            .fill(isHov ? barColor : barColor.opacity(0.8))
                            .frame(height: isHov ? 62 : 46)
                            .frame(minWidth: 1.5, maxWidth: 3.5)
                            .animation(.easeInOut(duration: 0.1), value: isHov)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    hoveredItem = hovering ? item : nil
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
                                withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: true)) {
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

    /// Prefer the poster's theme color when available, else the semantic taste color.
    private func barColor(_ item: BarcodeSlice) -> Color {
        if let hex = item.themeColorHex, let color = Color(hex: hex) {
            return color
        }
        guard let taste = TasteValue(rawValue: item.tasteValue) else { return .gray }
        return taste.color
    }
}
