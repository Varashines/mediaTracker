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
        .init(name: "Mac",        accent: "#0A84FF", darkBG: "#1C1D20", lightBG: "#F4F5F7", darkSurface: "#222428", lightSurface: "#ECEDEF", cardFillOpacity: 0.05),
        .init(name: "Trippy",     accent: "#3E9DB0", darkBG: "#1A1D1F", lightBG: "#F1F7F8", darkSurface: "#212426", lightSurface: "#E6EEF0", cardFillOpacity: 0.05),
        .init(name: "Chill",      accent: "#67A06B", darkBG: "#1A1E1B", lightBG: "#F2F7F2", darkSurface: "#212621", lightSurface: "#E6EDE4", cardFillOpacity: 0.05),
        .init(name: "Epic",       accent: "#8C66A8", darkBG: "#1B1A21", lightBG: "#F3F1F8", darkSurface: "#222130", lightSurface: "#E9E5F2", cardFillOpacity: 0.05),
        .init(name: "Emotional",  accent: "#D06A93", darkBG: "#1F1A1D", lightBG: "#F8F1F4", darkSurface: "#262024", lightSurface: "#EDE2E7", cardFillOpacity: 0.05),
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
        // Mac (index 0) uses the system accent for a true neutral default.
        if themePreset == 0 {
            self.accent = .accentColor
            return
        }
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

    /// Neutral background for DetailView — uses the Mac preset's neutral palette
    /// (ignores the active theme tint) so the detail page always sits on a clear base.
    func neutralBackground(for colorScheme: ColorScheme) -> Color {
        let mac = Self.presets[0]
        return Color(hex: isDarkActive ? mac.darkBG : mac.lightBG)
            ?? Color(white: isDarkActive ? 0.07 : 0.98)
    }

    /// Neutral card fill for DetailView — ignores the palette accent.
    func neutralCardFill(for colorScheme: ColorScheme) -> Color {
        Color.primary.opacity(isDarkActive ? 0.04 : 0.02)
    }

    // MARK: - Mood Color

    func updateMood(for colors: [Color], colorScheme: ColorScheme, force: Bool = false) {
        if SleepManager.shared.isAsleep { return }

        if !force && Date().timeIntervalSince(lastUpdate) < updateInterval {
            return
        }

        lastUpdate = Date()

        guard !colors.isEmpty else {
            self.categoryMoodColor = .clear
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
                // No withAnimation: animating the full-window MeshGradient on every
                // single-item update is wasteful. The throttle above already paces this.
                self.categoryMoodColor = finalColor
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
