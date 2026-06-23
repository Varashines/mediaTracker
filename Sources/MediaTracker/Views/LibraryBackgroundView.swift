import SwiftUI

struct LibraryBackgroundView: View {
    let mood: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear
            .adaptiveBackground()
            .ignoresSafeArea()
            .overlay {
                if #available(macOS 15, *) {
                    meshGradientBackground
                } else {
                    legacyGradientBackground
                }
            }
    }

    @available(macOS 15, *)
    private var meshGradientBackground: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5, 0.5], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ],
            colors: [
                mood.luminousAccent(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.06 : 0.12),
                .clear,
                mood.luminousAccent(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.03 : 0.06),
                .clear,
                .clear.opacity(0.3),
                .clear,
                mood.hueShift(by: 0.1).luminousAccent(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.04 : 0.08),
                .clear,
                mood.hueShift(by: 0.05).luminousAccent(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.02 : 0.05)
            ]
        )
        .allowsHitTesting(false)
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
