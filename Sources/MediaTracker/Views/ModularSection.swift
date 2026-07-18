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
                HStack(spacing: AppTheme.Spacing.mini) {
                    Image(systemName: icon)
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
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
