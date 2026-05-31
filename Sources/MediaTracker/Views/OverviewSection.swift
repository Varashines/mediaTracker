import SwiftUI

struct OverviewSection: View {
    let overview: String
    let themeColor: Color

    @Environment(\.colorScheme) var colorScheme


    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(AppTheme.Font.heading)
                    .foregroundStyle(themeColor.highContrastAccent(colorScheme: colorScheme))

                Text("SYNOPSIS")
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
            }

            Text(overview)
                .font(AppTheme.Font.bodyMedium)
                .lineSpacing(8)
                .foregroundStyle(.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }
}
