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
    /// Drop stroke + shadow while a fast-scroll gesture is active (clip only).
    var suppressEffects: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                // Hairline only when hovered or suppressed-off: idle cards skip
                // an extra stroke layer per cell during grid scroll.
                if !suppressEffects, isHovered {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            AppTheme.Colors.strokeHover(for: colorScheme),
                            lineWidth: 0.8
                        )
                }
            }
            // Always attach shadow — a structural `.if(isHovered)` here rewrites
            // ConditionalContent identity, remounts card content, and resets
            // CachedImage @State (logo flashes back to its title placeholder).
            .shadow(
                color: (!suppressEffects && isHovered)
                    ? AppTheme.Colors.shadowElevated(for: colorScheme)
                    : .clear,
                radius: (!suppressEffects && isHovered) ? 10 : 0,
                y: (!suppressEffects && isHovered) ? 5 : 0
            )
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func cardHoverChrome(radius: CGFloat, isHovered: Bool, suppressEffects: Bool = false) -> some View {
        modifier(CardHoverChrome(radius: radius, isHovered: isHovered, suppressEffects: suppressEffects))
    }
}
