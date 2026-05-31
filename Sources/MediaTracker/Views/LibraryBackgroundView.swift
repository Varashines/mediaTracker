import SwiftUI

struct LibraryBackgroundView: View {
    let mood: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear
            .adaptiveBackground()
            .ignoresSafeArea()
            .overlay {
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
}
