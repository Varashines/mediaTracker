import SwiftUI

extension AppTheme {
    struct Colors {
        @MainActor
        static var accent: Color {
            AppThemeCoordinator.shared.accent
        }

        @MainActor
        static func background(for colorScheme: ColorScheme) -> Color {
            AppThemeCoordinator.shared.background(for: colorScheme)
        }

        @MainActor
        static func cardFill(for colorScheme: ColorScheme) -> Color {
            AppThemeCoordinator.shared.cardFill(for: colorScheme)
        }
    }
}
