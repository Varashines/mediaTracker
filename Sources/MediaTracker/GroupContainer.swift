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
            RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                .fill(.ultraThinMaterial.opacity(scheme == .dark ? 0.28 : 0.52))
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: strokeColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isDangerZone ? 1.5 : 0.75
                )
        }
        .shadow(
            color: (scheme == .dark ? Color.black.opacity(0.2) : Color.black.opacity(0.04)),
            radius: 8,
            x: 0,
            y: 4
        )
    }

    private var strokeColors: [Color] {
        if isDangerZone {
            return [Color.red.opacity(0.6), Color.red.opacity(0.15)]
        }
        if let custom = customBorderColor {
            return [custom.opacity(0.4), custom.opacity(0.08)]
        }
        if scheme == .dark {
            return [.white.opacity(0.12), .white.opacity(0.03)]
        } else {
            return [.white.opacity(0.45), Color.primary.opacity(0.06)]
        }
    }
}
