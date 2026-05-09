import SwiftUI
import AppKit

extension CGSize {
    static let thumbSmall = CGSize(width: 200, height: 300)
    static let thumbMedium = CGSize(width: 400, height: 600)
    static let thumbLarge = CGSize(width: 800, height: 1200)
    static let backdropLarge = CGSize(width: 2000, height: 1125)
}

extension Color {
    static let detailAccent = Color.blue

    static func semanticGreen(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color.green
        } else {
            return Color(red: 0.0, green: 0.6, blue: 0.2)
        }
    }

    static func semanticRed(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color.red
        } else {
            return Color(red: 0.75, green: 0.1, blue: 0.1)
        }
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

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

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

    static func randomVibrant(for colorScheme: ColorScheme) -> Color {
        let hues: [Double] = [0.0, 0.1, 0.15, 0.45, 0.55, 0.65, 0.75, 0.85]
        let randomHue = hues.randomElement() ?? 0.5
        let saturation: Double = colorScheme == .dark ? 0.25 : 0.35
        let brightness: Double = colorScheme == .dark ? 0.95 : 0.8
        return Color(hue: randomHue, saturation: saturation, brightness: brightness)
    }

    /// Returns a version of the color that is optimized for small UI elements (icons/labels).
    /// It boosts brightness on dark backgrounds and maintains saturation.
    /// Returns a version of the color optimized for background washes and gradients.
    func luminousAccent(colorScheme: ColorScheme) -> Color {
        guard let nsc = NSColor(self).usingColorSpace(.sRGB) else { return self }
        
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        nsc.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        // Prevent grayscale colors (like .primary) from turning red
        if saturation < 0.05 {
            if colorScheme == .dark {
                return Color(white: Double(max(min(brightness, 0.75), 0.6)))
            } else {
                return Color(white: Double(max(brightness, 0.98)))
            }
        }
        
        if colorScheme == .dark {
            // Phase 5 Refinement: Moodier, less neon.
            return Color(hue: Double(hue), saturation: Double(max(saturation, 0.3)), brightness: Double(max(min(brightness, 0.75), 0.6)))
        } else {
            // Phase 5 Refinement: Airy, luminous wash.
            return Color(hue: Double(hue), saturation: Double(max(saturation, 0.4)), brightness: Double(max(brightness, 0.98)))
        }
    }

    /// Returns a version of the color optimized for text, icons, and small UI elements.
    func highContrastAccent(colorScheme: ColorScheme) -> Color {
        guard let nsc = NSColor(self).usingColorSpace(.sRGB) else { return self }
        
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        nsc.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        // Prevent grayscale colors (like .primary) from turning red
        if saturation < 0.05 {
            if colorScheme == .dark {
                return Color(white: Double(max(brightness, 0.9)))
            } else {
                return Color(white: Double(min(brightness, 0.45)))
            }
        }
        
        if colorScheme == .dark {
            // On dark backgrounds, ensure brightness is at least 0.9 and saturation is healthy
            return Color(hue: Double(hue), saturation: Double(max(saturation, 0.6)), brightness: Double(max(brightness, 0.9)))
        } else {
            // On light backgrounds, ensure it's deep enough (darkened) for high readability
            return Color(hue: Double(hue), saturation: Double(max(saturation, 0.8)), brightness: Double(min(brightness, 0.45)))
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
                        colors: [.clear, .white.opacity(0.15), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width * 2)
                    .offset(x: -width + (width * 2 * phase))
                    .rotationEffect(.degrees(30))
                }
                .mask(content)
            }
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}
