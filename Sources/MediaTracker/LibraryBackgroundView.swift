import SwiftUI

struct LibraryBackgroundView: View {
    let mood: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: [
                colorScheme == .dark ? .clear : mood.opacity(0.03),
                .clear
            ],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
        .ignoresSafeArea()
    }
}
