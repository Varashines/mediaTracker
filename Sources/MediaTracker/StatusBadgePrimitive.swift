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
        .liquidGlassPill(
            accentColor: bgAccent.opacity(colorScheme == .dark ? 0.3 : 0.4),
            isSolid: isSolid,
            progress: nil,
            hPadding: isCompact ? 0 : 10,
            vPadding: isCompact ? 0 : 4
        )
        .overlay {
            // AUTHORITATIVE CIRCULAR PROGRESS (Matches Season Tab pattern)
            if let progress = progress, progress > 0 && progress < 1.0 {
                Circle()
                    .inset(by: 1.25) // Half of the stroke width to sit perfectly on the edge
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(
                        Color.blueToGreen(progress: progress),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}
