import SwiftUI

/// Shared hover chrome for library cards: a theme-aware hairline that
/// strengthens on hover plus ambient → elevated shadow and a rounded hit area.
///
/// Rest: `strokeDefault` + ambient shadow. Hover: `strokeHover` + elevated.
/// Scale and content transitions stay per-card — they need each card's own
/// hover state. The border is drawn *inside* (`strokeBorder`) so card-level
/// `scaleEffect` can't make it shimmer.
struct CardHoverChrome: ViewModifier {
    var radius: CGFloat
    var isHovered: Bool

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        isHovered
                            ? AppTheme.Colors.strokeHover(for: colorScheme)
                            : AppTheme.Colors.strokeDefault(for: colorScheme),
                        lineWidth: 0.8
                    )
            }
            .shadow(
                color: isHovered
                    ? AppTheme.Colors.shadowElevated(for: colorScheme)
                    : AppTheme.Colors.shadowAmbient(for: colorScheme),
                radius: isHovered ? 10 : 5,
                y: isHovered ? 5 : 2
            )
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func cardHoverChrome(radius: CGFloat, isHovered: Bool) -> some View {
        modifier(CardHoverChrome(radius: radius, isHovered: isHovered))
    }
}
