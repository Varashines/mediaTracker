import SwiftUI

struct OverviewSection: View {
    let overview: String
    let themeColor: Color

    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded = false

    private var surfaceColor: Color {
        AppTheme.Colors.surfaceGhost(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(AppTheme.Font.title)
                    .foregroundStyle(themeColor.highContrastAccent(colorScheme: colorScheme))

                Text("SYNOPSIS")
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(.secondary)
                    .kerning(1.2)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(overview)
                    .font(AppTheme.Font.bodyMedium)
                    .lineSpacing(8)
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 4)
                    .overlay(alignment: .bottom) {
                        if !isExpanded && overview.count > 200 {
                            LinearGradient(
                                stops: [
                                    .init(color: surfaceColor.opacity(0), location: 0),
                                    .init(color: surfaceColor, location: 0.85)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 40)
                            .allowsHitTesting(false)
                        }
                    }

                if overview.count > 200 {
                    Button(isExpanded ? "Show Less" : "Show More") {
                        withAnimation(AppTheme.Animation.easeInOut) {
                            isExpanded.toggle()
                        }
                    }
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(themeColor.highContrastAccent(colorScheme: colorScheme))
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
            }
        }
        .padding(16)
        .background(surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
    }
}
