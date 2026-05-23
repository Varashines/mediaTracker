import SwiftUI

struct LibraryBackgroundView: View {
    let mood: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: [
                mood.opacity(colorScheme == .dark ? 0.06 : 0.03),
                .clear
            ],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
        .ignoresSafeArea()
    }
}
