import SwiftUI
import Observation

@Observable @MainActor
class AppThemeCoordinator {
    static let shared = AppThemeCoordinator()

    var categoryMoodColor: Color = .clear
    private var lastUpdate: Date = .distantPast
    private let updateInterval: TimeInterval = 1.5

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

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        for color in colors {
            guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else { continue }
            r += nsColor.redComponent
            g += nsColor.greenComponent
            b += nsColor.blueComponent
        }

        let count = CGFloat(colors.count)
        let avgColor = NSColor(red: r/count, green: g/count, blue: b/count, alpha: 1)

        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        avgColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let scaledAlpha = (colorScheme == .dark ? 0.04 : 0.15) * intensity
        let finalColor = Color(nsColor: NSColor(
            calibratedHue: hue,
            saturation: saturation * (colorScheme == .dark ? 0.15 : 0.4),
            brightness: colorScheme == .dark ? 0.12 : 0.98,
            alpha: scaledAlpha
        ))

        withAnimation(AppTheme.Animation.springGentle) {
            self.categoryMoodColor = finalColor
        }
    }
}
