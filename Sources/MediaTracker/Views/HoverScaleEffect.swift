import SwiftUI

/// Standardized hover effect with configurable scale level, shadow, and themed glow.
/// Replaces ad-hoc `.onHover` + `.scaleEffect` + `.shadow` patterns across the app.
struct HoverScaleEffect: ViewModifier {
    enum ScaleLevel {
        case subtle    // 1.02 — small cards, settings rows
        case normal    // 1.04 — grid posters, collection cards
        case prominent // 1.06 — hero cards, featured items

        var scale: CGFloat {
            switch self {
            case .subtle: return 1.02
            case .normal: return 1.04
            case .prominent: return 1.06
            }
        }
    }

    let level: ScaleLevel
    var themeColor: Color? = nil
    var shadowEnabled: Bool = true

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? level.scale : 1.0)
            .shadow(
                color: shadowColor,
                radius: isHovered ? shadowRadius : 0,
                y: isHovered ? shadowY : 0
            )
            .animation(AppTheme.Animation.springSnappy, value: isHovered)
            .onHover { isHovered = $0 }
    }

    private var shadowColor: Color {
        if isHovered, let themeColor {
            return themeColor.opacity(colorScheme == .dark ? 0.2 : 0.15)
        }
        return .clear
    }

    private var shadowRadius: CGFloat {
        switch level {
        case .subtle: return 6
        case .normal: return 10
        case .prominent: return 14
        }
    }

    private var shadowY: CGFloat {
        switch level {
        case .subtle: return 3
        case .normal: return 5
        case .prominent: return 7
        }
    }
}

extension View {
    func hoverScaled(
        _ level: HoverScaleEffect.ScaleLevel = .normal,
        themeColor: Color? = nil,
        shadow: Bool = true
    ) -> some View {
        modifier(HoverScaleEffect(level: level, themeColor: themeColor, shadowEnabled: shadow))
    }
}
