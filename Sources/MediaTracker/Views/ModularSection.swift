import SwiftUI

struct ModularSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: 0) {
                HStack(spacing: AppTheme.Spacing.small) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color == .secondary ? AppTheme.Colors.accent : color)
                        .padding(5)
                        .background(
                            Circle()
                                .fill((color == .secondary ? AppTheme.Colors.accent : color).opacity(0.15))
                        )
                    Text(title.uppercased())
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
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

            GlassCard(material: .ultraThinMaterial, cornerRadius: AppTheme.Radius.large, shadowed: true) {
                content
                    .padding(AppTheme.Spacing.medium)
            }
        }
    }
}
