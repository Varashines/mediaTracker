import SwiftUI

struct ModularSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                    Text(title.uppercased())
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                        .kerning(0.8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
                Spacer()
            }

            content
                .padding(AppTheme.Spacing.medium)
                .background {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                        .fill(Color.primary.opacity(scheme == .dark ? 0.04 : 0.02))
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                        .stroke(Color.primary.opacity(scheme == .dark ? 0.08 : 0.05), lineWidth: 0.5)
                )
        }
    }
}
