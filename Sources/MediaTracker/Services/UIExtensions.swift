import SwiftUI
import AppKit

extension CGSize {
    static let thumbTiny = AppTheme.Thumbnail.tiny
    static let thumbSmall = AppTheme.Thumbnail.small
    static let thumbMedium = AppTheme.Thumbnail.medium
    static let thumbLarge = AppTheme.Thumbnail.large
    static let thumbCompact = AppTheme.Thumbnail.compact
    static let backdropLarge = AppTheme.Thumbnail.backdropLarge
    static let backdropCompact = AppTheme.Thumbnail.backdropCompact
}

extension Color {

    static func semanticGreen(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color.green
        } else {
            return Color(red: 0.15, green: 0.75, blue: 0.3)
        }
    }

    static func semanticRed(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color.red
        } else {
            return Color(red: 0.75, green: 0.1, blue: 0.1)
        }
    }


    /// Returns a Color that linearly interpolates from pure blue (progress=0) to pure green (progress=1).
    static func blueToGreen(progress: Double) -> Color {
        let p = min(max(progress, 0), 1)
        // Transition from deep blue to vibrant green
        return Color(red: 0.0, green: 0.4 + (p * 0.6), blue: 1.0 - (p * 0.6))
    }

    var isLightColor: Bool {
        guard let rgbColor = NSColor(self).usingColorSpace(.sRGB) else { return false }
        var r: CGFloat
        var g: CGFloat
        var b: CGFloat
        var a: CGFloat
        (r, g, b, a) = (0, 0, 0, 0)
        rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.5
    }

    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        // Accept #RGB (3 hex digits) and expand to #RRGGBB.
        if hexSanitized.count == 3 {
            hexSanitized = hexSanitized.map { "\($0)\($0)" }.joined()
        }

        // Accept 6- or 8-digit hex. 8-digit includes alpha which we drop (we always
        // render opaque in the theme system).
        guard hexSanitized.count == 6 || hexSanitized.count == 8 else {
            return nil
        }

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        guard let rgbColor = NSColor(self).usingColorSpace(.sRGB) else {
            return "000000"
        }
        let r = Float(rgbColor.redComponent)
        let g = Float(rgbColor.greenComponent)
        let b = Float(rgbColor.blueComponent)
        return String(
            format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }



    /// Returns a version of the color optimized for background washes and gradients.
    func luminousAccent(colorScheme: ColorScheme) -> Color {
        let o = self.oklch
        
        // Handle grayscale
        if o.c < 0.02 {
            if colorScheme == .dark {
                return Color(white: max(min(o.l, 0.8), 0.65))
            } else {
                return Color(white: max(min(o.l, 0.92), 0.82))
            }
        }
        
        if colorScheme == .dark {
            // Phase 5 Refinement: Perceptually uniform moodiness - boosted for visibility.
            return Color.fromOKLCH(l: max(min(o.l, 0.85), 0.7), c: max(o.c, 0.22), h: o.h)
        } else {
            // Phase 5 Refinement: Perceptually uniform airiness.
            return Color.fromOKLCH(l: max(min(o.l, 0.92), 0.82), c: max(o.c, 0.18), h: o.h)
        }
    }

    /// Returns a version of the color optimized for text, icons, and small UI elements.
    func highContrastAccent(colorScheme: ColorScheme) -> Color {
        let o = self.oklch

        // Handle grayscale
        if o.c < 0.02 {
            if colorScheme == .dark {
                return Color(white: max(o.l, 0.95))
            } else {
                return Color(white: min(o.l, 0.35))
            }
        }

        if colorScheme == .dark {
            // On dark backgrounds, ensure perceptual lightness and chroma are high for vibrancy
            return Color.fromOKLCH(l: max(o.l, 0.92), c: max(o.c, 0.3), h: o.h)
        } else {
            // On light backgrounds, ensure it's deep enough for WCAG contrast but highly saturated
            return Color.fromOKLCH(l: min(o.l, 0.45), c: max(o.c, 0.20), h: o.h)
        }
    }


    /// Returns a color with a slight hue shift for organic gradients.
    func hueShift(by amount: Double) -> Color {
        guard let nsc = NSColor(self).usingColorSpace(.sRGB) else { return self }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsc.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        
        var newHue = h + CGFloat(amount)
        if newHue > 1.0 { newHue -= 1.0 }
        if newHue < 0.0 { newHue += 1.0 }
        
        return Color(hue: Double(newHue), saturation: Double(s), brightness: Double(b))
    }
}

// MARK: - Shimmering Effect
extension View {
    func shimmering() -> some View {
        modifier(ShimmeringModifier())
    }
}

struct ShimmeringModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    let width = geo.size.width
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.22), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width * 2)
                    .offset(x: -width + (width * 2.5 * phase))
                    .rotationEffect(.degrees(15))
                }
                .mask(content)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}



struct SubSectionHeader: View {
    let title: String
    
    init(_ title: String) {
        self.title = title
    }
    
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .tracking(1.2)
    }
}

// MARK: - Perceptual Color Math (OKLCH)
extension Color {
    struct OKLCH {
        var l: Double // Lightness (0-1)
        var c: Double // Chroma (0-0.4)
        var h: Double // Hue (0-360)
    }

    var oklch: OKLCH {
        guard let nsc = NSColor(self).usingColorSpace(.sRGB) else { return OKLCH(l: 0.5, c: 0, h: 0) }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsc.getRed(&r, green: &g, blue: &b, alpha: &a)

        // Linear sRGB
        let lr = r <= 0.04045 ? r / 12.92 : pow((r + 0.055) / 1.055, 2.4)
        let lg = g <= 0.04045 ? g / 12.92 : pow((g + 0.055) / 1.055, 2.4)
        let lb = b <= 0.04045 ? b / 12.92 : pow((b + 0.055) / 1.055, 2.4)

        // sRGB to LMS
        let l_ = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
        let m_ = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
        let s_ = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb

        let l_s = pow(max(0, l_), 1/3)
        let m_s = pow(max(0, m_), 1/3)
        let s_s = pow(max(0, s_), 1/3)

        // LMS to OKLAB
        let L = 0.2104542553 * l_s + 0.7936177850 * m_s - 0.0040720468 * s_s
        let a_ = 1.9779984951 * l_s - 2.4285922050 * m_s + 0.4505937099 * s_s
        let b_ = 0.0259040371 * l_s + 0.7827717662 * m_s - 0.8086757660 * s_s

        // OKLAB to OKLCH
        let C = sqrt(a_*a_ + b_*b_)
        var H = atan2(b_, a_) * 180 / .pi
        if H < 0 { H += 360 }

        return OKLCH(l: Double(L), c: Double(C), h: Double(H))
    }

    static func fromOKLCH(l: Double, c: Double, h: Double, alpha: Double = 1.0) -> Color {
        let hr = h * .pi / 180
        let a_ = c * cos(hr)
        let b_ = c * sin(hr)

        let l_s = l + 0.3963377774 * a_ + 0.2158037573 * b_
        let m_s = l - 0.1055613458 * a_ - 0.0638541728 * b_
        let s_s = l - 0.0894841775 * a_ - 1.2914855480 * b_

        let l_ = l_s * l_s * l_s
        let m_ = m_s * m_s * m_s
        let s_ = s_s * s_s * s_s

        let lr = 4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_
        let lg = -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_
        let lb = -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_

        func fromLinear(_ c: CGFloat) -> CGFloat {
            return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1/2.4) - 0.055
        }

        return Color(red: Double(max(0, min(1, fromLinear(lr)))),
                     green: Double(max(0, min(1, fromLinear(lg)))),
                     blue: Double(max(0, min(1, fromLinear(lb)))),
                     opacity: alpha)
    }
}

// MARK: - Skeleton Pulse
struct SkeletonPulseModifier: ViewModifier {
    @State private var isAnimating = false
    func body(content: Content) -> some View {
        content
            .opacity(isAnimating ? 0.5 : 0.85)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}

extension View {
    func skeletonPulse() -> some View {
        self.modifier(SkeletonPulseModifier())
    }

    func adaptiveBackground() -> some View {
        self.modifier(AdaptiveBackgroundModifier())
    }

    @ViewBuilder
    func glassButtonStyle() -> some View {
        self.buttonStyle(.plain)
    }


}

extension View {
    @ViewBuilder
    func toolbarTitleMenuIfAvailable<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        if #available(macOS 15, *) {
            self.toolbarTitleMenu(content: content)
        } else {
            self
        }
    }
}
struct AdaptiveBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("theme_preference") private var themePreference = 0
    @AppStorage("dark_theme_style") private var darkThemeStyle = 0
    @AppStorage("custom_theme_palette") private var customThemePalette = 0

    func body(content: Content) -> some View {
        content
            .background(AppTheme.Colors.background(for: colorScheme))
    }
}

