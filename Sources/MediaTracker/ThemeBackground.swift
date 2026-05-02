import SwiftUI

struct ThemeBackground: ViewModifier {
    var networkOverride: String? = nil
    var tintOverride: Color? = nil
    var activeCategory: String? = nil
    var disableBrandBackground: Bool = false
    @AppStorage("theme_style") private var themeStyle: ThemeStyle = .standard
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        let isAsleep = SleepManager.shared.isAsleep
        let isDiscover = activeCategory == "Discover" || activeCategory == "DiscoverBeta"
        
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

                        if let tint = tintOverride {
                            tint.opacity(colorScheme == .dark ? 0.35 : 0.25)
                        } else if let network = networkOverride,
                            let color = NetworkThemeManager.shared.color(for: network)
                        {
                            color.opacity(colorScheme == .dark ? 0.35 : 0.25)
                        } else {
                            AppThemeCoordinator.shared.categoryMoodColor.opacity(colorScheme == .dark ? 0.35 : 0.25)
                        }
                        
                        // Optimized Static Ambience (Replaces energy-heavy Metal shader)
                        ZStack {
                            RadialGradient(colors: [Color.pink.opacity(isDiscover ? 0.08 : 0.04), .clear], center: .topTrailing, startRadius: 0, endRadius: 800)
                            RadialGradient(colors: [Color.teal.opacity(isDiscover ? 0.08 : 0.04), .clear], center: .bottomLeading, startRadius: 0, endRadius: 800)
                        }
                    }
                }
                .ignoresSafeArea()
            }
    }
}

extension View {
    func appBackground(network: String? = nil, category: String? = nil, tint: Color? = nil, disableBrandBackground: Bool = false) -> some View {
        self.modifier(ThemeBackground(networkOverride: network, tintOverride: tint, activeCategory: category, disableBrandBackground: disableBrandBackground))
    }
}
