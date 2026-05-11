import SwiftUI

struct StatusBadgePrimitive: View {
    let label: String
    let accentColor: Color
    let isSolid: Bool
    let progress: Double?
    var isCompact: Bool = false
    var foregroundColor: Color? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let contrastColor = accentColor.highContrastAccent(colorScheme: colorScheme)
        let bgAccent = accentColor.luminousAccent(colorScheme: colorScheme)
        
        HStack(spacing: 0) {
            if !label.isEmpty {
                Text(label.uppercased())
                    .font(.system(size: 7.5, weight: .black, design: .rounded))
                    .kerning(1.0)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(minHeight: 20)
        .foregroundStyle(foregroundColor ?? (isSolid ? .white : contrastColor))
        .liquidGlassPill(
            accentColor: bgAccent.opacity(colorScheme == .dark ? 0.3 : 0.4),
            isSolid: isSolid,
            progress: nil,
            isMicro: true,
            hPadding: 10,
            vPadding: 4
        )
        .overlay {
            if let progress = progress, progress > 0 && progress < 1.0 {
                Capsule()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.blueToGreen(progress: progress),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
            }
        }
    }
}
