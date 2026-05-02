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

        // If solid, always white. If frosted, use primary (adaptive black/white).
        let defaultForeground = isSolid ? Color.white : .primary
        let foreground = foregroundColor ?? defaultForeground

        // If solid, high opacity. If frosted, subtle tint.
        let tintOpacity = isSolid ? 1.0 : (isLight ? 0.35 : 0.5)

        return
            content
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background {
                if isAsleep {
                    // FLAT BACKGROUND DURING SLEEP
                    Capsule()
                        .fill(isSolid ? accentColor : Color.gray.opacity(0.2))
                } else {
                    ZStack(alignment: .leading) {
                        if isSolid {
                            Capsule()
                                .fill(accentColor.opacity(tintOpacity))
                        } else {
                            ZStack {
                                Capsule()
                                    .fill(.ultraThickMaterial)
                                Capsule()
                                    .fill(accentColor.opacity(tintOpacity))
                            }
                        }

                        // Glow & Fill Progress
                        if let progress = progress {
                            Capsule()
                                .fill(foreground.opacity(0.15))
                                .scaleEffect(x: CGFloat(min(max(progress, 0), 1)), anchor: .leading)
                        }
                    }
                }
            }
            .clipShape(Capsule())
            .overlay {
                // Subtle stroke for definition
                if !isAsleep {
                    Capsule()
                        .stroke(
                            accentColor.opacity(isSolid ? 1.0 : (isLight ? 0.7 : 0.5)), lineWidth: 0.5)
                }
            }
            .overlay(alignment: .bottom) {
                // Glowing bottom line for progress
                if let progress = progress, !isAsleep {
                    VStack {
                        Spacer()
                        Capsule()
                            .fill(foreground.opacity(0.8))
                            .frame(height: 1.5)
                            .scaleEffect(x: CGFloat(min(max(progress, 0), 1)), anchor: .leading)
                            .shadow(color: foreground.opacity(0.5), radius: 2, x: 0, y: 0)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 1)
                    }
                }
            }
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
