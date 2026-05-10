import SwiftUI

struct StatusBadgePrimitive: View {
    let label: String
    let systemImage: String
    let accentColor: Color
    let isSolid: Bool
    let progress: Double?
    var isCompact: Bool = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let contrastColor = accentColor.highContrastAccent(colorScheme: colorScheme)
        let bgAccent = accentColor.luminousAccent(colorScheme: colorScheme)
        
        HStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
        }
        .frame(width: 24, height: 24)
        .foregroundStyle(isSolid ? .white : contrastColor)
        .liquidGlassPill(accentColor: bgAccent.opacity(colorScheme == .dark ? 0.3 : 0.4), isSolid: isSolid, progress: progress)
    }
}
