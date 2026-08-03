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
    var themePreset: Int = 0
    var reduceVisualEffects: Bool = false
    
    static var isReducingVisualEffects: Bool { shared.reduceVisualEffects }

    private var lastReload: Date = .distantPast
    private let reloadDebounce: TimeInterval = 0.1

    // MARK: - Theme Preset Definition

    struct ThemePreset {
        let name: String
        let accent: String
        let darkBG: String
        let lightBG: String
        let darkSurface: String
        let lightSurface: String
        let cardFillOpacity: Double
    }

    static let presets: [ThemePreset] = [
        .init(name: "Blue",    accent: "#007AFF", darkBG: "#1E1E1E", lightBG: "#F2F2F7", darkSurface: "#222222", lightSurface: "#E5E5EA", cardFillOpacity: 0.05),
        .init(name: "Beige",   accent: "#D4A574", darkBG: "#2A2420", lightBG: "#FCF6EE", darkSurface: "#2C2824", lightSurface: "#F0E8DC", cardFillOpacity: 0.05),
        .init(name: "Slate",   accent: "#8E8E93", darkBG: "#1C1C1E", lightBG: "#F2F2F7", darkSurface: "#222224", lightSurface: "#E5E5EA", cardFillOpacity: 0.06),
        .init(name: "Sage",    accent: "#7B9B6D", darkBG: "#1C1E1A", lightBG: "#F5F7F2", darkSurface: "#22241E", lightSurface: "#E8EAE2", cardFillOpacity: 0.05),
        .init(name: "Crimson", accent: "#FF2D55", darkBG: "#25171A", lightBG: "#FFF4F6", darkSurface: "#2C1B1F", lightSurface: "#FFE6EA", cardFillOpacity: 0.05),
        .init(name: "Amber",   accent: "#FF9500", darkBG: "#262017", lightBG: "#FFF9F0", darkSurface: "#2D251A", lightSurface: "#FFEDD5", cardFillOpacity: 0.05),
    ]

    private var activePreset: ThemePreset {
        Self.presets[safe: themePreset] ?? Self.presets[0]
    }

    // MARK: - Init

    private init() {
        reloadSettings()

        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let now = Date()
                guard now.timeIntervalSince(self.lastReload) >= self.reloadDebounce else { return }
                self.lastReload = now
                self.reloadSettings()
            }
        }
    }

    // MARK: - Settings

    private func reloadSettings() {
        let newPref = UserDefaults.standard.integer(forKey: "theme_preference")
        let newPreset = UserDefaults.standard.integer(forKey: "theme_preset")
        let newReduceEffects = UserDefaults.standard.bool(forKey: "reduce_visual_effects")

        if themePreference != newPref || themePreset != newPreset || reduceVisualEffects != newReduceEffects {
            themePreference = newPref
            themePreset = newPreset
            reduceVisualEffects = newReduceEffects
            updateThemeColors()
        }
    }

    func updateThemeColors() {
        let preset = activePreset
        self.accent = Color(hex: preset.accent) ?? .accentColor
    }

    func appearanceDidChange() {
        updateThemeColors()
    }

    // MARK: - Dark/Light Detection

    var isDarkActive: Bool {
        if themePreference == 0 {
            #if os(macOS)
            guard let app = NSApp else { return false }
            return app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            #else
            return false
            #endif
        }
        return themePreference == 2
    }

    // MARK: - Color Resolution

    func background(for colorScheme: ColorScheme) -> Color {
        let preset = activePreset
        return Color(hex: isDarkActive ? preset.darkBG : preset.lightBG)
            ?? Color(white: isDarkActive ? 0.07 : 0.98)
    }

    func surface(for colorScheme: ColorScheme) -> Color {
        let preset = activePreset
        return Color(hex: isDarkActive ? preset.darkSurface : preset.lightSurface)
            ?? background(for: colorScheme)
    }

    func cardFill(for colorScheme: ColorScheme) -> Color {
        let preset = activePreset
        let accentColor = Color(hex: preset.accent) ?? .accentColor
        return accentColor.opacity(isDarkActive ? preset.cardFillOpacity : preset.cardFillOpacity * 0.6)
    }

    // MARK: - Mood Color

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

// MARK: - Safe Array Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
