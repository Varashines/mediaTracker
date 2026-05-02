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
        HStack(spacing: isCompact ? 0 : 4) {
            Image(systemName: systemImage)
                .font(.system(size: isCompact ? 11 : 10, weight: .bold))
            
            if !isCompact {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
            }
        }
        .liquidGlassPill(accentColor: accentColor, isSolid: isSolid, progress: progress)
    }
}
