import SwiftUI

extension AppTheme {
    struct Colors {
        static var accent: Color { Color.accentColor }

        @MainActor
        static func background(for colorScheme: ColorScheme) -> Color {
            let pref = UserDefaults.standard.integer(forKey: "theme_preference")
            let darkStyle = UserDefaults.standard.integer(forKey: "dark_theme_style")
            
            let isSystem = pref == 0
            let isDarkPref = pref == 2
            let isCurrentlyDark = isDarkPref || (isSystem && colorScheme == .dark)
            
            if isCurrentlyDark && darkStyle == 1 {
                return Color(white: 0.0) // AMOLED
            }
            return Color(white: isCurrentlyDark ? 0.11 : 0.96)
        }

        static func cardFill(for colorScheme: ColorScheme) -> Color {
            Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.02)
        }
    }
}
