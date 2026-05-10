import SwiftUI

struct OverviewSection: View {
    let overview: String
    let themeColor: Color

    @Environment(\.colorScheme) var colorScheme
    @AppStorage("theme_style") private var themeStyle: ThemeStyle = .standard

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(themeColor.gradient)

                Text("SYNOPSIS")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
            }

            Text(overview)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .lineSpacing(8)
                .foregroundStyle(.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }
}
