import SwiftUI

struct MetadataLine: View {
    let icon: String?
    let value: String?
    let themeColor: Color
    var isLanguage: Bool = false

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if let value = value, !value.isEmpty {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(themeColor.highContrastAccent(colorScheme: colorScheme))
                }
                
                Text(displayValue)
                    .foregroundStyle(.primary)
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .padding(.horizontal, 4)
            .minimumScaleFactor(0.9)
            .liquidGlassPill(accentColor: themeColor.luminousAccent(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.15 : 0.4), isSolid: false)
        }
    }
    
    private var displayValue: String {
        guard let value = value else { return "" }
        if isLanguage {
            return Locale.current.localizedString(forLanguageCode: value) ?? value.uppercased()
        }
        return value
    }
}
