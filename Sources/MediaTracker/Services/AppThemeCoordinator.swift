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
        let isDark = isDarkActive
        
        // Compute Accent
        if customThemePalette == 1 {
            self.accent = isDark ? (Color(hex: "#C87A53") ?? .accentColor) : (Color(hex: "#5C8075") ?? .accentColor)
        } else if customThemePalette == 2 {
            self.accent = Color(hex: "#6E7BB8") ?? .accentColor
        } else {
            self.accent = .accentColor
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
        if isDark {
            if customThemePalette == 1 {
                return Color(hex: "#19221F") ?? Color(white: 0.11)
            } else if customThemePalette == 2 {
                return Color(hex: "#151C25") ?? Color(white: 0.11)
            }
            return Color(white: 0.11)
        } else {
            if customThemePalette == 1 {
                return Color(hex: "#FAF6EE") ?? Color(white: 0.96)
            } else if customThemePalette == 2 {
                return Color(hex: "#F3F5F7") ?? Color(white: 0.96)
            }
            return Color(white: 0.96)
        }
    }

    func cardFill(for colorScheme: ColorScheme) -> Color {
        let isDark = isDarkActive
        if customThemePalette == 1 {
            return Color(hex: isDark ? "#222B28" : "#F1EBE0") ?? Color.primary.opacity(isDark ? 0.04 : 0.02)
        } else if customThemePalette == 2 {
            return Color(hex: isDark ? "#1E2633" : "#E8ECEF") ?? Color.primary.opacity(isDark ? 0.04 : 0.02)
        }
        return Color.primary.opacity(isDark ? 0.04 : 0.02)
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
