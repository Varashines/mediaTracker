import SwiftUI

struct LibraryBackgroundView: View {
    let mood: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if AppThemeCoordinator.isReducingVisualEffects {
            Color.clear
                .adaptiveBackground()
                .ignoresSafeArea()
        } else {
            Color.clear
                .adaptiveBackground()
                .ignoresSafeArea()
                .overlay {
                    legacyGradientBackground
                }
        }
    }

    private var legacyGradientBackground: some View {
        LinearGradient(
            colors: [
                mood.opacity(colorScheme == .dark ? 0.04 : 0.1),
                .clear
            ],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
    }
}
