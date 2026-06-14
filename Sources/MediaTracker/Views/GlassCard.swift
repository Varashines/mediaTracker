import SwiftUI

/// Canonical "rounded card" container with optional tinted background and stroke.
/// Use this in place of one-off `RoundedRectangle(...).fill(.ultraThinMaterial).overlay(stroke)`
/// stacks. The settings card and the detail page's `ModularSection` both render this.
struct GlassCard<Content: View>: View {
    var color: Color = .clear
    var material: Material = .ultraThinMaterial
    var cornerRadius: CGFloat = AppTheme.Radius.medium
    var shadowed: Bool = true
    var isHovered: Bool = false
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(material)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    color != .clear
                        ? color.opacity(scheme == .dark ? 0.25 : 0.12)
                        : AppTheme.Colors.strokeDefault(for: scheme),
                    lineWidth: 0.8
                )
        }
        .shadow(
            color: shadowed
                ? (isHovered
                    ? AppTheme.Colors.shadowElevated(for: scheme)
                    : AppTheme.Colors.shadowAmbient(for: scheme))
                : .clear,
            radius: isHovered ? AppTheme.Shadow.elevated.radius : AppTheme.Shadow.card.radius,
            y: isHovered ? AppTheme.Shadow.elevated.y : AppTheme.Shadow.card.y
        )
    }
}
