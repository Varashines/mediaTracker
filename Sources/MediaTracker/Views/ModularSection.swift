import SwiftUI

struct ModularSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

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
                        .kerning(0.8)
                }
                .padding(.horizontal, AppTheme.Spacing.small)
                .padding(.vertical, AppTheme.Spacing.micro)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
                Spacer()
            }

            GlassCard(material: .ultraThinMaterial, cornerRadius: AppTheme.Radius.large, shadowed: true) {
                content
                    .padding(AppTheme.Spacing.medium)
            }
        }
    }
}
