import SwiftUI

struct OverviewSection: View {
    let overview: String
    let themeColor: Color

    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded = false
    @State private var isHovering = false

    private var surfaceColor: Color {
        AppTheme.Colors.surfaceGhost(for: colorScheme)
    }

    private var hasTruncation: Bool {
        !isExpanded && overview.count > 200
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
                    .overlay(alignment: .bottom) {
                        if hasTruncation {
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
