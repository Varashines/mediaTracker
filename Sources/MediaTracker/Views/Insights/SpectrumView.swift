import SwiftUI

struct SpectrumView: View {
    let items: [BarcodeSlice]
    @State private var hoveredItem: BarcodeSlice?
    @Environment(\.colorScheme) private var colorScheme

    private var validItems: [BarcodeSlice] {
        items.filter { $0.themeColorHex != nil || $0.tasteValue != TasteValue.none.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            header
            barcodeArea
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
        .padding(.vertical, AppTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .fill(AppTheme.Colors.accent.opacity(colorScheme == .dark ? 0.06 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(AppTheme.Colors.accent.opacity(0.15), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("CINEMA DNA SIGNATURE")
                .font(AppTheme.Font.caption)
                .foregroundStyle(.secondary)
                .kerning(1.2)

            Spacer()

            if let item = hoveredItem {
                HStack(spacing: 4) {
                    Circle()
                        .fill(tasteColor(item.tasteValue))
                        .frame(width: 6, height: 6)
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
            HStack(spacing: 1) {
                Spacer(minLength: 0)
                ForEach(Array(validItems.prefix(150).enumerated()), id: \.element.id) { index, item in
                    let isCurrentHovered = hoveredItem?.id == item.id
                    let barColor = tasteColor(item.tasteValue)
                    Rectangle()
                        .fill(isCurrentHovered ? barColor : barColor.opacity(0.8))
                        .frame(height: isCurrentHovered ? 44 : 32)
                        .frame(minWidth: 1.5, maxWidth: 3)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            withAnimation(AppTheme.Animation.springSnappy) {
                                hoveredItem = hovering ? item : nil
                            }
                        }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 50)
        }
    }

    private func tasteColor(_ value: String) -> Color {
        guard let taste = TasteValue(rawValue: value) else { return .secondary }
        return taste.color
    }
}
