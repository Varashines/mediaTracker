import SwiftUI

struct OverviewSection: View {
    let overview: String
    let themeColor: Color

    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded = false


    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(AppTheme.Font.title)
                    .foregroundStyle(themeColor.highContrastAccent(colorScheme: colorScheme))

                Text("SYNOPSIS")
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(.secondary)
                    .kerning(1.2)

                Spacer()

                if overview.count > 200 {
                    Button(isExpanded ? "Show Less" : "Show More") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(themeColor.highContrastAccent(colorScheme: colorScheme))
                    .buttonStyle(.plain)
                }
            }

            Text(overview)
                .font(AppTheme.Font.bodyMedium)
                .lineSpacing(8)
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(AppTheme.Colors.surfaceGhost(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
    }
}
