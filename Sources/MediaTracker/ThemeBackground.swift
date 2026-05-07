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

    @State private var phase: Double = 0

    func body(content: Content) -> some View {
        let isAsleep = SleepManager.shared.isAsleep
        let isDiscover = activeCategory == "Discover" || activeCategory == "DiscoverBeta"

        let color = tintOverride ?? (networkOverride.flatMap { NetworkThemeManager.shared.color(for: $0) })?.luminousAccent(colorScheme: colorScheme) ?? AppThemeCoordinator.shared.categoryMoodColor
        let warmColor = warmTintOverride ?? color.hueShift(by: 0.04)
        let coolColor = coolTintOverride ?? color.hueShift(by: -0.04)

        content
            .background {
                ZStack {
                    if isAsleep {
                        Color(NSColor.windowBackgroundColor)
                    } else {
                        if themeStyle == .brand && !disableBrandBackground {
                            appAccent.brandBackground(for: colorScheme)
                        } else {
                            Color(NSColor.windowBackgroundColor)
                        }

                        // Phase 5: High-End Aurora Mesh (macOS 15)
                        let meshPoints: [SIMD2<Float>] = [
                            [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                            [0.0, 0.5], [Float(0.5 + 0.1 * sin(phase)), Float(0.5 + 0.1 * cos(phase))], [1.0, 0.5],
                            [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                        ]

                        let meshColors: [Color] = [
                            coolColor.opacity(0.1), color.opacity(0.2), warmColor.opacity(0.1),
                            color.opacity(0.15), color.opacity(colorScheme == .dark ? 0.35 : 0.25), color.opacity(0.15),
                            warmColor.opacity(0.1), color.opacity(0.1), coolColor.opacity(0.1)
                        ]

                        MeshGradient(
                            width: 3,
                            height: 3,
                            points: meshPoints,
                            colors: meshColors
                        )
                        .blur(radius: 50)
                        .saturation(1.2)

                        // Static Ambient Accents
                        ZStack {
                            RadialGradient(colors: [Color.pink.opacity(isDiscover ? 0.08 : 0.04), .clear], center: .topTrailing, startRadius: 0, endRadius: 800)
                            RadialGradient(colors: [Color.teal.opacity(isDiscover ? 0.08 : 0.04), .clear], center: .bottomLeading, startRadius: 0, endRadius: 800)
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
                    phase = .pi * 2
                }
            }
    }
}

extension View {
    func appBackground(network: String? = nil, category: String? = nil, tint: Color? = nil, warmTint: Color? = nil, coolTint: Color? = nil, disableBrandBackground: Bool = false) -> some View {
        self.modifier(ThemeBackground(networkOverride: network, tintOverride: tint, warmTintOverride: warmTint, coolTintOverride: coolTint, activeCategory: category, disableBrandBackground: disableBrandBackground))
    }
}
