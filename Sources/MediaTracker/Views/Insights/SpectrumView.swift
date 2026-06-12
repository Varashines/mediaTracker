import SwiftUI

struct SpectrumView: View {
    let items: [BarcodeSlice]
    @State private var hoveredItem: BarcodeSlice?
    @State private var isScanning = false
    @State private var scanLineWidth: CGFloat = 0
    @State private var scanPosition: CGFloat = 0
    @State private var barColors: [String: Color] = [:]
    @Environment(\.colorScheme) private var colorScheme

    private var validItems: [BarcodeSlice] {
        items.filter { $0.themeColorHex != nil || $0.tasteValue != TasteValue.none.rawValue }
    }

    var body: some View {
        InsightGlassTile {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                header
                barcodeArea
                legend
            }
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
        .onAppear { precomputeColors() }
    }

    private func precomputeColors() {
        var colors: [String: Color] = [:]
        for item in validItems.prefix(100) {
            if let hex = item.themeColorHex, let c = Color(hex: hex) {
                colors[item.id] = c
            } else {
                let taste = TasteValue(rawValue: item.tasteValue) ?? .none
                colors[item.id] = taste.color
            }
        }
        barColors = colors
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("COLLECTION SPECTRUM")
                .font(AppTheme.Font.caption)
                .foregroundStyle(.secondary)
                .kerning(1.2)

            Spacer()

            if let item = hoveredItem {
                HStack(spacing: 4) {
                    Text(item.title)
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(item.tasteValue == TasteValue.none.rawValue ? "UNRATED" : item.tasteValue.uppercased())
                        .font(AppTheme.Font.caption2)
                        .foregroundStyle(tasteColor(item.tasteValue))
                }
                .transition(.opacity)
            } else {
                Text("HOVER TO SCAN")
                    .font(AppTheme.Font.mono)
                    .foregroundStyle(.secondary.opacity(0.4))
            }
        }
    }

    @ViewBuilder
    private var barcodeArea: some View {
        if validItems.isEmpty {
            CuteEmptyState(icon: "barcode.viewfinder", message: "Add titles to generate your spectrum", color: .secondary)
                .frame(height: 44)
        } else {
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    Spacer(minLength: 0)
                    ForEach(validItems.prefix(100)) { item in
                        let isCurrentHovered = hoveredItem?.id == item.id
                        let barColor = barColors[item.id] ?? .primary.opacity(0.15)
                        RoundedRectangle(cornerRadius: 2.0)
                            .fill(isCurrentHovered ? barColor : barColor.opacity(0.8))
                            .frame(height: 32)
                            .frame(minWidth: 1.5, maxWidth: 6)
                            .scaleEffect(y: isCurrentHovered ? 1.15 : 1.0)
                            .shadow(color: isCurrentHovered ? barColor.opacity(0.5) : .clear, radius: isCurrentHovered ? 6 : 0)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                withAnimation(AppTheme.Animation.springSnappy) {
                                    if hovering { hoveredItem = item; startScan() }
                                    else if hoveredItem?.id == item.id { hoveredItem = nil; stopScan() }
                                }
                            }
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 44)

                if isScanning {
                    AppTheme.Colors.accent.opacity(0.4)
                        .frame(width: 2, height: 44)
                        .shadow(color: AppTheme.Colors.accent.opacity(0.5), radius: 6)
                        .offset(x: scanPosition)
                }
            }
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            scanLineWidth = geo.size.width
                            if isScanning { animateScan() }
                        }
                        .onChange(of: isScanning) { _, new in
                            if new { animateScan() }
                        }
                }
                .frame(width: 0, height: 0)
                .hidden()
            }
        }
    }

    @ViewBuilder
    private var legend: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle().fill(.pink).frame(width: 6, height: 6)
                Text("Loved").font(AppTheme.Font.tiny)
            }
            HStack(spacing: 4) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("Liked").font(AppTheme.Font.tiny)
            }
            HStack(spacing: 4) {
                Circle().fill(.red.opacity(0.6)).frame(width: 6, height: 6)
                Text("Disliked").font(AppTheme.Font.tiny)
            }
            HStack(spacing: 4) {
                Circle().fill(.primary.opacity(0.3)).frame(width: 6, height: 6)
                Text("Theme Color").font(AppTheme.Font.tiny)
            }
        }
        .foregroundStyle(.secondary.opacity(0.6))
    }

    private func startScan() {
        isScanning = true
    }

    private func stopScan() {
        isScanning = false
        scanPosition = 0
    }

    private func animateScan() {
        guard scanLineWidth > 0 else { return }
        scanPosition = 0
        withAnimation(Animation.linear(duration: 2.2).repeatForever(autoreverses: true)) {
            scanPosition = scanLineWidth
        }
    }

    private func tasteColor(_ value: String) -> Color {
        guard let taste = TasteValue(rawValue: value) else { return .secondary }
        return taste.color
    }
}
