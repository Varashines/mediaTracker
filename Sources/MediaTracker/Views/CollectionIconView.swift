import SwiftUI

extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || unicodeScalars.count > 1)
    }
}

extension String {
    var isEmoji: Bool {
        for scalar in unicodeScalars {
            if scalar.properties.isEmoji {
                return true
            }
        }
        return false
    }
}

struct CollectionIconView: View {
    let systemImage: String
    var font: Font = AppTheme.Font.title3
    var color: Color? = nil
    
    var body: some View {
        if systemImage.isEmoji {
            Text(systemImage)
                .font(font)
        } else {
            Image(systemName: systemImage)
                .font(font)
                .foregroundStyle(color ?? .primary)
        }
    }
}
