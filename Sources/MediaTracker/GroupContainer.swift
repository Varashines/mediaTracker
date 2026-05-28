import SwiftUI

struct GroupContainer<Content: View>: View {
    @Environment(\.colorScheme) var scheme
    var customBorderColor: Color? = nil
    var isDangerZone: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.vertical, AppTheme.Spacing.small)
        .padding(.horizontal, AppTheme.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(scheme == .dark ? Color(white: 0.1) : Color(white: 0.97))
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .strokeBorder(strokeColor, lineWidth: isDangerZone ? 1.5 : 0.75)
        }
    }

    private var strokeColor: Color {
        if isDangerZone {
            return Color.red.opacity(0.5)
        }
        if let custom = customBorderColor {
            return custom.opacity(0.3)
        }
        return AppTheme.Colors.cardFill(for: scheme)
    }
}
