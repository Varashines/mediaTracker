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
                                .font(AppTheme.Font.caption)
                                .foregroundStyle(.secondary)
                            Text(item.tasteValue == "None" ? "UNRATED" : item.tasteValue.uppercased())
                                .font(AppTheme.Font.caption2)
                                .foregroundStyle(item.tasteValue == "Love" ? .red : item.tasteValue == "Like" ? .blue : item.tasteValue == "Dislike" ? .orange : .secondary)
                        }
                        .transition(.opacity)
                    } else {
                        Text("HOVER TO SCAN")
                            .font(AppTheme.Font.mono)
                            .foregroundStyle(.secondary.opacity(0.4))
                    }
                }

                let validItems = items.filter { $0.themeColorHex != nil }
                if validItems.isEmpty {
                    HStack {
                        Spacer()
                        Text("Add rated or themed titles to generate signature")
                            .font(AppTheme.Font.body)
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
                                    switch item.tasteValue {
                                    case "Love": return .red
                                    case "Like": return .blue
                                    case "Dislike": return .orange
                                    default: return .primary.opacity(0.15)
                                    }
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
                                Color.accentColor.opacity(0.4)
                                    .frame(width: 2, height: 44)
                                    .shadow(color: Color.accentColor.opacity(0.9), radius: 6, x: 0, y: 0)
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
