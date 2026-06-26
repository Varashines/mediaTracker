import SwiftUI

struct OverviewSection: View {
    let overview: String
    let themeColor: Color

    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded = false
    @State private var visibleHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @State private var isHovering = false
    @State private var hasTruncation = false

    private var surfaceColor: Color {
        AppTheme.Colors.surfaceGhost(for: colorScheme)
    }

    private func updateTruncation(visible: CGFloat, full: CGFloat) {
        if !isExpanded {
            hasTruncation = full > visible + 2
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
            HStack(spacing: AppTheme.Spacing.tiny) {
                Image(systemName: "quote.opening")
                    .font(AppTheme.Font.title)
                    .foregroundStyle(themeColor.highContrastAccent(colorScheme: colorScheme))

                Text("SYNOPSIS")
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(.secondary)
                    .kerning(AppTheme.Kerning.wide)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(overview)
                    .font(AppTheme.Font.bodyMedium)
                    .lineSpacing(AppTheme.Spacing.tiny)
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 3)
                    .background(
                        GeometryReader { visibleGeo in
                            Color.clear
                                .onAppear {
                                    visibleHeight = visibleGeo.size.height
                                    updateTruncation(visible: visibleGeo.size.height, full: fullHeight)
                                }
                                .onChange(of: visibleGeo.size.height) { _, newHeight in
                                    visibleHeight = newHeight
                                    updateTruncation(visible: newHeight, full: fullHeight)
                                }
                        }
                    )
                    .background(
                        Text(overview)
                            .font(AppTheme.Font.bodyMedium)
                            .lineSpacing(AppTheme.Spacing.tiny)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(0)
                            .allowsHitTesting(false)
                            .background(
                                GeometryReader { fullGeo in
                                    Color.clear
                                        .onAppear {
                                            fullHeight = fullGeo.size.height
                                            updateTruncation(visible: visibleHeight, full: fullGeo.size.height)
                                        }
                                        .onChange(of: fullGeo.size.height) { _, newHeight in
                                            fullHeight = newHeight
                                            updateTruncation(visible: visibleHeight, full: newHeight)
                                        }
                                }
                            )
                    )
                    .overlay(alignment: .bottom) {
                        if !isExpanded && hasTruncation {
                            LinearGradient(
                                stops: [
                                    .init(color: surfaceColor.opacity(0), location: 0),
                                    .init(color: surfaceColor, location: 0.85)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 30)
                            .allowsHitTesting(false)
                        }
                    }
            }
        }
        .padding(AppTheme.Spacing.medium)
        .background(surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
        .scaleEffect(isHovering && hasTruncation ? 1.015 : 1.0)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            if hasTruncation {
                withAnimation(AppTheme.Animation.springGentle) {
                    isExpanded.toggle()
                }
            }
        }
        .animation(AppTheme.Animation.springSnappy, value: isHovering)
    }
}
