import SwiftUI
import Observation

@Observable @MainActor
class AppThemeCoordinator {
    static let shared = AppThemeCoordinator()
    
    var categoryMoodColor: Color = .clear
    private var lastUpdate: Date = .distantPast
    private let updateInterval: TimeInterval = 1.5 // Debounce mood updates significantly to save CPU

    func updateMood(for colors: [Color], colorScheme: ColorScheme, force: Bool = false) {
        // LOCKDOWN: Skip theme math if the app is hibernating
        if SleepManager.shared.isAsleep { return }

        // Debounce logic: prevent too many background shifts during active scroll
        if !force && Date().timeIntervalSince(lastUpdate) < updateInterval {
            return
        }
        
        lastUpdate = Date()
        
        guard !colors.isEmpty else {
            withAnimation(.easeInOut(duration: 0.8)) {
                self.categoryMoodColor = .clear
            }
            return
        }
        
        // Average the colors and desaturate
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        for color in colors {
            let nsColor = NSColor(color)
            r += nsColor.redComponent
            g += nsColor.greenComponent
            b += nsColor.blueComponent
            a += nsColor.alphaComponent
        }
        
        let count = CGFloat(colors.count)
        let avgColor = NSColor(red: r/count, green: g/count, blue: b/count, alpha: a/count)
        
        // Desaturate and set opacity for a "Glass" look
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        avgColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        let finalColor = Color(nsColor: NSColor(
            calibratedHue: hue,
            saturation: saturation * 0.4, // desaturate for subtlety
            brightness: colorScheme == .dark ? 0.15 : 0.98,
            alpha: 0.15 // translucent
        ))
        
        withAnimation(.easeInOut(duration: 0.8)) {
            self.categoryMoodColor = finalColor
        }
    }
}
