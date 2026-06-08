import SwiftUI

struct GlassCard<Content: View>: View {
    var fill: AnyShapeStyle = AnyShapeStyle(.ultraThinMaterial)
    var cornerRadius: CGFloat = AppTheme.Radius.large
    @Environment(\.colorScheme) var colorScheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 0.5)
            )
    }
}

extension GlassCard where Content == EmptyView {
    init(fill: AnyShapeStyle = AnyShapeStyle(.ultraThinMaterial), cornerRadius: CGFloat = AppTheme.Radius.large) {
        self.fill = fill
        self.cornerRadius = cornerRadius
        self.content = { EmptyView() }
    }
}
