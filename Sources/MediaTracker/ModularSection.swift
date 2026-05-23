import SwiftUI

struct ModularSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary.opacity(0.7))
                Text(title.uppercased())
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary.opacity(0.7))
                    .kerning(0.8)
                Spacer()
            }
            .padding(.leading, AppTheme.Spacing.micro)

            content
                .padding(AppTheme.Spacing.medium)
                .background {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(scheme == .dark ? 0.4 : 0.6))
                }
                .background(color.opacity(scheme == .dark ? 0.05 : 0.02) as Color)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
        }
    }
}
