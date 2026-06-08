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

        // MARK: - Semantic Surface Fills

        /// Barely visible background — ghost fills, very subtle tints
        @MainActor
        static func surfaceGhost(for colorScheme: ColorScheme) -> Color {
            Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.02)
        }

        /// Subtle card fills — list rows, grid cells
        @MainActor
        static func surfaceSubtle(for colorScheme: ColorScheme) -> Color {
            Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04)
        }

        /// Muted fills — hover states, active areas
        @MainActor
        static func surfaceMuted(for colorScheme: ColorScheme) -> Color {
            Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06)
        }

        // MARK: - Semantic Strokes

        /// Default border — inactive, resting state
        @MainActor
        static func strokeDefault(for colorScheme: ColorScheme) -> Color {
            Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06)
        }

        /// Hover border — interactive elements on hover
        @MainActor
        static func strokeHover(for colorScheme: ColorScheme) -> Color {
            Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.12)
        }

        /// Accent-colored border — selected, active, themed elements
        @MainActor
        static func strokeAccent(color: Color, for colorScheme: ColorScheme) -> Color {
            color.opacity(colorScheme == .dark ? 0.3 : 0.25)
        }

        // MARK: - Semantic Shadows

        /// Ambient shadow — resting cards, subtle depth
        @MainActor
        static func shadowAmbient(for colorScheme: ColorScheme) -> Color {
            .black.opacity(colorScheme == .dark ? 0.15 : 0.05)
        }

        /// Elevated shadow — hovered cards, floating elements
        @MainActor
        static func shadowElevated(for colorScheme: ColorScheme) -> Color {
            .black.opacity(colorScheme == .dark ? 0.2 : 0.08)
        }

        // MARK: - Status Colors

        /// Watched / completed status
        @MainActor
        static func statusWatched(for colorScheme: ColorScheme) -> Color {
            Color.semanticGreen(for: colorScheme)
        }

        /// Active / in-progress status
        @MainActor
        static func statusActive(for colorScheme: ColorScheme) -> Color {
            accent
        }
    }
}
