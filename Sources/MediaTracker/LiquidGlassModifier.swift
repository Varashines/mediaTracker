import SwiftUI

struct LiquidGlassModifier: ViewModifier {
    let accentColor: Color
    let isSolid: Bool
    let foregroundColor: Color?
    let progress: Double?
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 4
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        let isLight = accentColor.isLightColor
        let isAsleep = SleepManager.shared.isAsleep

        let defaultForeground = isSolid ? Color.white : .primary
        let foreground = foregroundColor ?? defaultForeground
        let tintOpacity = isSolid ? 0.9 : (isLight ? 0.2 : 0.3)

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
                        if isSolid {
                            Capsule()
                                .fill(accentColor.opacity(tintOpacity))
                        } else {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Capsule()
                                        .fill(accentColor.opacity(tintOpacity))
                                }
                        }
                    }
                }
            }
            .clipShape(Capsule())
            .overlay {
                if !isAsleep {
                    Capsule()
                        .stroke(accentColor.opacity(0.3), lineWidth: 0.5)
                }
            }
    }

    private func clampedProgress(_ val: Double) -> Double {
        return min(max(val, 0), 1)
    }
}

extension View {
    func liquidGlassPill(
        accentColor: Color, isSolid: Bool = false, foregroundColor: Color? = nil, progress: Double? = nil,
        hPadding: CGFloat = 10, vPadding: CGFloat = 4
    ) -> some View {
        self.modifier(
            LiquidGlassModifier(
                accentColor: accentColor, isSolid: isSolid, foregroundColor: foregroundColor, progress: progress,
                horizontalPadding: hPadding, verticalPadding: vPadding))
    }
}
