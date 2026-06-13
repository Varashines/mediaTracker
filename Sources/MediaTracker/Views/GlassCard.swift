import SwiftUI

/// Canonical "rounded card" container with optional tinted background and stroke.
/// Use this in place of one-off `RoundedRectangle(...).fill(.ultraThinMaterial).overlay(stroke)`
/// stacks. The settings card and the detail page's `ModularSection` both render this.
struct GlassCard<Content: View>: View {
    var color: Color = .clear
    var material: Material = .ultraThinMaterial
    var cornerRadius: CGFloat = AppTheme.Radius.medium
    var shadowed: Bool = true
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
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color != .clear ? color.opacity(scheme == .dark ? 0.04 : 0.02) : .clear)
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
        .shadow(color: shadowed ? AppTheme.Colors.shadowAmbient(for: scheme) : .clear, radius: 6, y: 3)
    }
}
