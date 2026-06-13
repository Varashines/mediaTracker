import SwiftUI

/// UI Standardization - Centralized Design System
struct AppTheme {
    struct Spacing {
        static let micro: CGFloat = 4
        static let tiny: CGFloat = 8
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
        static let section: CGFloat = 40
        static let pageMargin: CGFloat = 40
    }

    struct Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 20
        static let card: CGFloat = 24
    }

    struct Font {
        // Display sizes
        static let heroTitle = SwiftUI.Font.system(size: 60, weight: .heavy, design: .rounded)
        static let largeTitle = SwiftUI.Font.system(size: 40, weight: .heavy, design: .rounded)

        // Title sizes
        static let title = SwiftUI.Font.system(size: 28, weight: .bold, design: .rounded)
        static let titleLarge = SwiftUI.Font.system(size: 26, weight: .bold, design: .rounded)
        static let title2 = SwiftUI.Font.system(size: 24, weight: .bold, design: .rounded)
        static let title3 = SwiftUI.Font.system(size: 20, weight: .bold, design: .rounded)

        // Heading / subtitle
        static let subtitle = SwiftUI.Font.system(size: 16, weight: .bold, design: .rounded)
        static let heading = SwiftUI.Font.system(size: 14, weight: .semibold, design: .rounded)

        // Body sizes
        static let bodyMedium = SwiftUI.Font.system(size: 15, weight: .medium, design: .rounded)
        static let body = SwiftUI.Font.system(size: 13, weight: .regular, design: .rounded)
        static let bodyBold = SwiftUI.Font.system(size: 13, weight: .bold, design: .rounded)

        // Label / caption sizes
        static let label = SwiftUI.Font.system(size: 12, weight: .regular, design: .rounded)
        static let caption = SwiftUI.Font.system(size: 11, weight: .bold, design: .rounded)
        static let caption2 = SwiftUI.Font.system(size: 10, weight: .semibold, design: .rounded)

        // Small sizes
        static let small = SwiftUI.Font.system(size: 9, weight: .semibold, design: .rounded)
        static let smallBold = SwiftUI.Font.system(size: 9, weight: .bold, design: .rounded)
        static let tiny = SwiftUI.Font.system(size: 8, weight: .bold, design: .rounded)
        static let badge = SwiftUI.Font.system(size: 7.5, weight: .semibold, design: .rounded)

        // Settings
        static let settingsSectionHeader = SwiftUI.Font.system(size: 14, weight: .semibold, design: .rounded)
        static let settingsRowTitle = SwiftUI.Font.system(size: 14, weight: .medium, design: .rounded)
        static let settingsSubtitle = SwiftUI.Font.system(size: 11, weight: .regular, design: .rounded)

        // Monospaced
        static let mono = SwiftUI.Font.system(size: 9, weight: .regular, design: .monospaced)
    }

    struct ShadowConfig {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    struct Shadow {
        static let card = ShadowConfig(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
        static let elevated = ShadowConfig(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
    }

    struct Animation {
        static let springSnappy: SwiftUI.Animation = .spring(response: 0.3, dampingFraction: 0.7)
        static let springGentle: SwiftUI.Animation = .spring(response: 0.6, dampingFraction: 0.8)
        static let easeInOut: SwiftUI.Animation = .easeInOut(duration: 0.25)
    }

    struct Thumbnail {
        static let tiny = CGSize(width: 80, height: 120)
        static let small = CGSize(width: 160, height: 240)
        static let medium = CGSize(width: 400, height: 600)
        static let large = CGSize(width: 800, height: 1200)
        static let compact = CGSize(width: 210, height: 105)
        static let backdropLarge = CGSize(width: 2000, height: 1125)
        static let backdropCompact = CGSize(width: 400, height: 226)
    }

    /// Standardized icon sizes
    struct Icon {
        static let small = SwiftUI.Font.system(size: 11, weight: .medium)
        static let medium = SwiftUI.Font.system(size: 14, weight: .medium)
    }
}
