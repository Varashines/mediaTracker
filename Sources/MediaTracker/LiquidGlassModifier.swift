import SwiftUI

struct LiquidGlassModifier: ViewModifier {
    let accentColor: Color
    let isSolid: Bool
    let foregroundColor: Color?
    let progress: Double?
    var isMicro: Bool = false
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 4
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        let isAsleep = SleepManager.shared.isAsleep

        let defaultForeground = Color.white
        let foreground = foregroundColor ?? defaultForeground
        let tintOpacity = isSolid ? 0.95 : (accentColor.isLightColor ? 0.25 : 0.35)

        return content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .foregroundStyle(foreground)
            .background {
                if isAsleep {
                    Capsule()
                        .fill(isSolid ? accentColor : Color.gray.opacity(0.15))
                } else {
                    ZStack(alignment: .leading) {
                        if isMicro {
                            Capsule()
                                .fill(accentColor.opacity(tintOpacity))
                                .background(.ultraThinMaterial)
                        } else {
                            Capsule()
                                .fill(accentColor.opacity(tintOpacity))
                                .glassEffect(.regular, in: .capsule)
                        }
                        
                        // PROGRESS FILL
                        if let prog = progress, prog > 0 && prog < 1.0 {
                            GeometryReader { geo in
                                Capsule()
                                    .fill(accentColor.opacity(isSolid ? 1.0 : 0.7))
                                    .frame(width: geo.size.width * CGFloat(clampedProgress(prog)))
                            }
                        }
                    }
                }
            }
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    private func clampedProgress(_ val: Double) -> Double {
        return min(max(val, 0), 1)
    }
}

extension View {
    func liquidGlassPill(
        accentColor: Color, isSolid: Bool = false, foregroundColor: Color? = nil, progress: Double? = nil,
        isMicro: Bool = false, hPadding: CGFloat = 10, vPadding: CGFloat = 4
    ) -> some View {
        self.modifier(
            LiquidGlassModifier(
                accentColor: accentColor, isSolid: isSolid, foregroundColor: foregroundColor, progress: progress,
                isMicro: isMicro, horizontalPadding: hPadding, verticalPadding: vPadding))
    }
}
