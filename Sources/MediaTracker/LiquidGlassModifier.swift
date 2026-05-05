import SwiftUI

struct LiquidGlassModifier: ViewModifier {
    let accentColor: Color
    let isSolid: Bool
    let foregroundColor: Color?
    let progress: Double?
    @Environment(\.colorScheme) var colorScheme

    init(accentColor: Color, isSolid: Bool = false, foregroundColor: Color? = nil, progress: Double? = nil) {
        self.accentColor = accentColor
        self.isSolid = isSolid
        self.foregroundColor = foregroundColor
        self.progress = progress
    }

    func body(content: Content) -> some View {
        let isLight = accentColor.isLightColor
        let isAsleep = SleepManager.shared.isAsleep

        let defaultForeground = isSolid ? Color.white : .primary
        let foreground = foregroundColor ?? defaultForeground
        let tintOpacity = isSolid ? 0.9 : (isLight ? 0.2 : 0.3)

        return content
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
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

                        if let progress = progress {
                            Capsule()
                                .fill(foreground.opacity(0.1))
                                .scaleEffect(x: CGFloat(clampedProgress(progress)), anchor: .leading)
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
    func liquidGlassPill(accentColor: Color, isSolid: Bool = false, foregroundColor: Color? = nil, progress: Double? = nil)
        -> some View
    {
        self.modifier(
            LiquidGlassModifier(
                accentColor: accentColor, isSolid: isSolid, foregroundColor: foregroundColor, progress: progress))
    }
}
