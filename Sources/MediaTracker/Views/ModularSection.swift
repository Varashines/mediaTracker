import SwiftUI

struct ModularSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let effectiveColor = (color == .secondary.opacity(0.1) || color == .secondary) ? AppTheme.Colors.accent : color

        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: 0) {
                HStack(spacing: AppTheme.Spacing.small) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(effectiveColor.highContrastAccent(colorScheme: colorScheme))
                        .padding(5)
                        .background(
                            Circle()
                                .fill(effectiveColor.opacity(colorScheme == .dark ? 0.25 : 0.18))
                        )
                    Text(title.uppercased())
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(effectiveColor.highContrastAccent(colorScheme: colorScheme))
                        .kerning(AppTheme.Kerning.tight)
                }
                .padding(.horizontal, AppTheme.Spacing.small)
                .padding(.vertical, AppTheme.Spacing.micro)
                .background {
                    if AppThemeCoordinator.isReducingVisualEffects {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                            .fill(AppTheme.Colors.background(for: colorScheme))
                    } else {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                            .fill(.ultraThinMaterial)
                    }
                }
                Spacer()
            }

            GlassCard(color: effectiveColor, material: .ultraThinMaterial, cornerRadius: AppTheme.Radius.large, shadowed: true) {
                content
                    .padding(AppTheme.Spacing.medium)
            }
        }
    }
}
