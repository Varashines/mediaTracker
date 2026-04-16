import SwiftUI

struct LiquidGlassModifier: ViewModifier {
    let accentColor: Color
    let isSolid: Bool
    @Environment(\.colorScheme) var colorScheme

    init(accentColor: Color, isSolid: Bool = false) {
        self.accentColor = accentColor
        self.isSolid = isSolid
    }

    func body(content: Content) -> some View {
        let isLight = accentColor.isLightColor
        
        // If solid, always white. If frosted, adaptive.
        let foreground = isSolid ? Color.white : (isLight ? Color.black.opacity(0.85) : Color.white)
        // If solid, high opacity. If frosted, subtle tint.
        let tintOpacity = isSolid ? (colorScheme == .dark ? 0.8 : 0.9) : (isLight ? 0.35 : 0.5)
        
        return content
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background {
                ZStack {
                    // "Frosted" high-performance background
                    Capsule()
                        .fill(.ultraThickMaterial)
                    
                    Capsule()
                        .fill(accentColor.opacity(tintOpacity))
                }
            }
            .clipShape(Capsule())
            .overlay {
                // Subtle stroke for definition
                Capsule()
                    .stroke(accentColor.opacity(isSolid ? 1.0 : (isLight ? 0.7 : 0.5)), lineWidth: 0.5)
            }
    }
}

extension View {
    func liquidGlassPill(accentColor: Color, isSolid: Bool = false) -> some View {
        self.modifier(LiquidGlassModifier(accentColor: accentColor, isSolid: isSolid))
    }
}

extension Color {
    var isLightColor: Bool {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        // Perceived luminance formula
        let luminance = (0.299 * r + 0.587 * g + 0.114 * b)
        return luminance > 0.65
    }

    func toHex() -> String? {
        guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r, g, b: Double
        if hexSanitized.count == 6 {
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
            self.init(red: r, green: g, blue: b)
        } else {
            return nil
        }
    }
}
