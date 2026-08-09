import SwiftUI

/// Neutral claymorphic surface — the same puffed gradient + glossy highlight +
/// inner-depth-shadow treatment as the hero stat cards, but with no accent tint.
/// Used across Insights cards (Taste Profile rows, Hall of Fame) for a cohesive
/// "cute 3D" look that stays theme-agnostic.
struct ClaymorphicSurface: View {
    var cornerRadius: CGFloat = AppTheme.Radius.large
    var isHovered: Bool = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            // Puffed neutral background
            .fill(
                LinearGradient(
                    colors: [
                        Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.07),
                        Color.primary.opacity(colorScheme == .dark ? 0.03 : 0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            // Outer subtle border
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        Color.primary.opacity(isHovered
                            ? (colorScheme == .dark ? 0.18 : 0.16)
                            : (colorScheme == .dark ? 0.10 : 0.06)),
                        lineWidth: isHovered ? 1.0 : 0.6
                    )
            )
            // Inner Highlight (Glossy)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.40), lineWidth: 2.5)
                    .blur(radius: 1.2)
                    .offset(x: 1.2, y: 1.2)
                    .mask(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            )
            // Inner Shadow (Depth)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(colorScheme == .dark ? 0.32 : 0.06), lineWidth: 3)
                    .blur(radius: 1.5)
                    .offset(x: -1.5, y: -1.5)
                    .mask(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            )
    }
}
