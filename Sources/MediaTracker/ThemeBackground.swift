import SwiftUI

struct ThemeBackground: ViewModifier {
    var networkOverride: String? = nil
    var tintOverride: Color? = nil
    var warmTintOverride: Color? = nil
    var coolTintOverride: Color? = nil
    var activeCategory: String? = nil
    var disableBrandBackground: Bool = false
    @AppStorage("theme_style") private var themeStyle: ThemeStyle = .standard
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        let isAsleep = SleepManager.shared.isAsleep

        // Base Atmosphere Color
        let baseColor = tintOverride ?? (networkOverride.flatMap { NetworkThemeManager.shared.color(for: $0) })?.luminousAccent(colorScheme: colorScheme) ?? appAccent.color(for: colorScheme)
        
        content
            .background {
                ZStack {
                    if isAsleep {
                        Color(NSColor.windowBackgroundColor)
                    } else {
                        // 1. Solid Foundation
                        if themeStyle == .brand && !disableBrandBackground {
                            appAccent.brandBackground(for: colorScheme)
                        } else {
                            Color(NSColor.windowBackgroundColor)
                        }

                        // 2. The Static Nebula (Zero CPU Overload)
                        StaticNebulaView(color: baseColor)
                            .opacity(colorScheme == .dark ? 0.8 : 0.4)
                            .saturation(colorScheme == .dark ? 1.2 : 0.8)
                    }
                }
                .ignoresSafeArea()
            }
    }
}

/// A high-end, static cinematic background using radial gradients.
struct StaticNebulaView: View {
    let color: Color
    
    var body: some View {
        ZStack {
            // Main Atmosphere (Top Right)
            RadialGradient(
                colors: [color.opacity(0.15), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 900
            )
            
            // Secondary Bloom (Bottom Left)
            RadialGradient(
                colors: [color.opacity(0.1), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 700
            )
            
            // Subconscious Accent (Center Left)
            RadialGradient(
                colors: [color.opacity(0.05), .clear],
                center: UnitPoint(x: 0.2, y: 0.5),
                startRadius: 0,
                endRadius: 500
            )
        }
        .blur(radius: 40)
    }
}

extension View {
    func appBackground(network: String? = nil, category: String? = nil, tint: Color? = nil, warmTint: Color? = nil, coolTint: Color? = nil, disableBrandBackground: Bool = false) -> some View {
        self.modifier(ThemeBackground(networkOverride: network, tintOverride: tint, warmTintOverride: warmTint, coolTintOverride: coolTint, activeCategory: category, disableBrandBackground: disableBrandBackground))
    }
}
