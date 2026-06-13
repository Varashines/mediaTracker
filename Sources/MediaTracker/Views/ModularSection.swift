import SwiftUI

struct ModularSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .kerning(0.8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
                Spacer()
            }

            GlassCard(material: .ultraThinMaterial, cornerRadius: AppTheme.Radius.large, shadowed: false) {
                content
                    .padding(AppTheme.Spacing.medium)
            }
        }
    }
}
