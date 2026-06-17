import SwiftUI
import Observation

@Observable @MainActor
class AppThemeCoordinator {
    static let shared = AppThemeCoordinator()

    var categoryMoodColor: Color = .clear
    private var lastUpdate: Date = .distantPast
    private let updateInterval: TimeInterval = 1.5

    // Reactive Color Properties
    var accent: Color = .accentColor
    var themePreference: Int = 0
    var customThemePalette: Int = 0

    private init() {
        reloadSettings()
        
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadSettings()
            }
        }
    }

    private func reloadSettings() {
        let newPref = UserDefaults.standard.integer(forKey: "theme_preference")
        let newPalette = UserDefaults.standard.integer(forKey: "custom_theme_palette")
        
        if themePreference != newPref || customThemePalette != newPalette {
            themePreference = newPref
            customThemePalette = newPalette
            updateThemeColors()
        }
    }

    func updateThemeColors() {
        // Compute Accent
        switch customThemePalette {
        case 1:
            self.accent = Color(hex: "#C47A5A") ?? .accentColor  // Earth — warm terracotta
        case 2:
            self.accent = Color(hex: "#7B8CDE") ?? .accentColor  // Cool — slate indigo
        case 3:
            self.accent = Color(hex: "#10B981") ?? .accentColor  // Forest — deep emerald
        case 4:
            self.accent = Color(hex: "#3B82F6") ?? .accentColor  // Ocean — deep ocean
        case 5:
            self.accent = Color(hex: "#D97706") ?? .accentColor  // Dusk — warm amber
        case 6:
            self.accent = Color(hex: "#8B5CF6") ?? .accentColor  // Midnight — deep violet
        default:
            self.accent = .accentColor  // Standard
        }
    }

    var isDarkActive: Bool {
        if themePreference == 0 {
            #if os(macOS)
            return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            #else
            return false
            #endif
        }
        return themePreference == 2
    }

    func background(for colorScheme: ColorScheme) -> Color {
        let isDark = isDarkActive
        switch customThemePalette {
        case 1: // Earth — barely warm tint on grey base
            return Color(hex: isDark ? "#2D2B28" : "#F9F6F3") ?? Color(white: isDark ? 0.17 : 0.96)
        case 2: // Cool — barely cool tint on grey base
            return Color(hex: isDark ? "#2A2B30" : "#F6F7FA") ?? Color(white: isDark ? 0.17 : 0.96)
        case 3: // Forest — barely green tint on grey base
            return Color(hex: isDark ? "#2A2D2B" : "#F7FAF8") ?? Color(white: isDark ? 0.17 : 0.96)
        case 4: // Ocean — barely blue tint on grey base
            return Color(hex: isDark ? "#292C33" : "#F5F7FC") ?? Color(white: isDark ? 0.17 : 0.96)
        case 5: // Dusk — barely amber tint on grey base
            return Color(hex: isDark ? "#2D2A26" : "#FAF7F2") ?? Color(white: isDark ? 0.17 : 0.96)
        case 6: // Midnight — barely violet tint on grey base
            return Color(hex: isDark ? "#2A2830" : "#F7F5FA") ?? Color(white: isDark ? 0.17 : 0.96)
        default: // Standard — macOS grey
            return Color(white: isDark ? 0.17 : 0.96)
        }
    }

    func cardFill(for colorScheme: ColorScheme) -> Color {
        let isDark = isDarkActive
        switch customThemePalette {
        case 1, 2, 3, 4, 5, 6: // All tinted palettes — subtle card fill
            return Color.primary.opacity(isDark ? 0.05 : 0.03)
        default: // Standard — neutral card fill
            return Color.primary.opacity(isDark ? 0.04 : 0.02)
        }
    }

    func updateMood(for colors: [Color], colorScheme: ColorScheme, force: Bool = false) {
        if SleepManager.shared.isAsleep { return }

        if !force && Date().timeIntervalSince(lastUpdate) < updateInterval {
            return
        }

        lastUpdate = Date()

        guard !colors.isEmpty else {
            withAnimation(AppTheme.Animation.springGentle) {
                self.categoryMoodColor = .clear
            }
            return
        }

        let intensity = UserDefaults.standard.double(forKey: "background_intensity")
        let isDark = (colorScheme == .dark)

        // Move the (potentially expensive) sRGB + HSB math off the main actor. We capture
        // the color components on a background task, then commit the final Color back on
        // main with the gentle animation.
        let nsColors: [NSColor] = colors.compactMap { NSColor($0).usingColorSpace(.sRGB) }
        let isDarkSnapshot = isDark
        let intensitySnapshot = intensity

        Task.detached(priority: .utility) {
            guard !nsColors.isEmpty else { return }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            for c in nsColors {
                r += c.redComponent
                g += c.greenComponent
                b += c.blueComponent
            }
            let count = CGFloat(nsColors.count)
            let avgColor = NSColor(red: r/count, green: g/count, blue: b/count, alpha: 1)

            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            avgColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

            let scaledAlpha = (isDarkSnapshot ? 0.04 : 0.15) * intensitySnapshot
            let finalColor = Color(nsColor: NSColor(
                calibratedHue: hue,
                saturation: saturation * (isDarkSnapshot ? 0.15 : 0.4),
                brightness: isDarkSnapshot ? 0.12 : 0.98,
                alpha: scaledAlpha
            ))

            await MainActor.run {
                withAnimation(AppTheme.Animation.springGentle) {
                    self.categoryMoodColor = finalColor
                }
            }
        }
    }
}
