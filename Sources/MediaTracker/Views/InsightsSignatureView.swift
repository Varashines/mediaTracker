import SwiftUI

struct CinephileBarcodeView: View {
    let items: [BarcodeSlice]
    @State private var hoveredItem: BarcodeSlice?
    @State private var isScanning = false
    @State private var scanPosition: CGFloat = 0.0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                HStack {
                    Text("CINEPHILE SPECTRUM")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .kerning(1.2)

                    Spacer()

                    if let item = hoveredItem {
                        HStack(spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("·")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            let isNone = item.tasteValue == TasteValue.none.rawValue
                            Text(isNone ? "UNRATED" : item.tasteValue.uppercased())
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle({
                                    guard let taste = TasteValue(rawValue: item.tasteValue) else { return Color.secondary }
                                    return taste.color
                                }())
                        }
                        .transition(.opacity)
                    } else {
                        Text("HOVER TO SCAN")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.4))
                    }
                }

                let validItems = items.filter { $0.themeColorHex != nil }
                if validItems.isEmpty {
                    HStack {
                        Spacer()
                        Text("Add rated or themed titles to generate signature")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(height: 32)
                } else {
                    ZStack(alignment: .leading) {
                        HStack(spacing: 2) {
                            Spacer(minLength: 0)
                            ForEach(validItems.prefix(100)) { item in
                                let isCurrentHovered = hoveredItem?.id == item.id
                                    let barColor: Color = {
                                    if let hex = item.themeColorHex, let c = Color(hex: hex) {
                                        return c
                                    }
                                    guard let taste = TasteValue(rawValue: item.tasteValue) else { return .primary.opacity(0.15) }
                                    return taste.color
                                }()

                                RoundedRectangle(cornerRadius: 1.0)
                                    .fill(isCurrentHovered ? barColor : barColor.opacity(0.8))
                                    .frame(height: 32)
                                    .frame(minWidth: 1.5, maxWidth: 6)
                                    .scaleEffect(y: isCurrentHovered ? 1.3 : 1.0)
                                    .shadow(color: isCurrentHovered ? barColor.opacity(0.8) : Color.clear, radius: isCurrentHovered ? 6 : 0)
                                    .contentShape(Rectangle())
                                    .onHover { isHovered in
                                        withAnimation(AppTheme.Animation.springSnappy) {
                                            if isHovered {
                                                hoveredItem = item
                                                isScanning = true
                                            } else if hoveredItem?.id == item.id {
                                                hoveredItem = nil
                                                isScanning = false
                                            }
                                        }
                                    }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(height: 44)

                        if isScanning {
                            GeometryReader { geo in
                                AppTheme.Colors.accent.opacity(0.4)
                                    .frame(width: 2, height: 44)
                                    .shadow(color: AppTheme.Colors.accent.opacity(0.9), radius: 6, x: 0, y: 0)
                                    .offset(x: scanPosition * geo.size.width)
                                    .onAppear {
                                        scanPosition = 0.0
                                        withAnimation(Animation.linear(duration: 2.2).repeatForever(autoreverses: true)) {
                                            scanPosition = 1.0
                                        }
                                    }
                                    .onDisappear {
                                        scanPosition = 0.0
                                    }
                            }
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
    }
}
