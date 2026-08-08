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
                    .font(AppTheme.Font.caption)
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
                    .mask(
                        LinearGradient(
                            stops: hasTruncation
                                ? [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 0.6),
                                    .init(color: .clear, location: 1)
                                ]
                                : [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 1)
                                ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(alignment: .bottom) {
                        if hasTruncation && isHovering {
                            Text("Tap to expand")
                                .font(AppTheme.Font.caption)
                                .foregroundStyle(.tertiary)
                                .offset(y: -4)
                                .transition(.opacity)
                        }
                    }
            }
        }
        .padding(AppTheme.Spacing.medium)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(AppThemeCoordinator.isReducingVisualEffects
                    ? AnyShapeStyle(surfaceColor)
                    : AnyShapeStyle(.ultraThinMaterial))
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 0.5)
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            if overview.count > 200 {
                withAnimation(AppTheme.Animation.springGentle) {
                    isExpanded.toggle()
                }
            }
        }
    }
}
