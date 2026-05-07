import SwiftUI

struct OverviewSection: View {
    let overview: String
    let themeColor: Color

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(themeColor.highContrastAccent(colorScheme: colorScheme))
                    .frame(width: 4, height: 18)

                Text("SYNOPSIS")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
            }

            Text(overview)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .lineSpacing(6)
                .foregroundStyle(.primary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }
}
