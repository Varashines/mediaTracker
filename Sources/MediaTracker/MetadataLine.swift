import SwiftUI

struct MetadataLine: View {
    let label: String
    let value: String?
    let themeColor: Color
    var isLanguage: Bool = false

    var body: some View {
        if let value = value, !value.isEmpty {
            HStack(spacing: 4) {
                Text("\(label):")
                    .foregroundStyle(.secondary)
                Text(displayValue)
                    .foregroundStyle(.primary)
            }
            .font(.system(size: 11, weight: .semibold))
            .minimumScaleFactor(0.9)
            .liquidGlassPill(accentColor: themeColor.opacity(0.12), isSolid: false)
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
