import SwiftUI

struct TrendingPosterCard: View, Equatable {
    let item: MediaSearchResult
    var isInLibrary: Bool = false
    @Environment(\.isFastScrolling) private var isFastScrolling
    @State private var isHovered = false

    nonisolated static func == (lhs: TrendingPosterCard, rhs: TrendingPosterCard) -> Bool {
        lhs.item.id == rhs.item.id && lhs.isInLibrary == rhs.isInLibrary
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            posterImage
                .frame(width: 160, height: 240)

            // Corner indicator badge (visible when in library)
            if isInLibrary && !isHovered {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .background(Color.green.opacity(0.9), in: Circle())
                    .padding(8)
                    .transition(.opacity)
            }

            if isHovered {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Image(systemName: isInLibrary ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(AppTheme.Font.title)
                    .foregroundStyle(isInLibrary ? .green : .white)
                    .shadow(radius: 4)
                    .padding(12)
                    .transition(.opacity)

                VStack(spacing: 3) {
                    Text(item.title)
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if isInLibrary {
                        Text("In Library")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.opacity)
            }
        }
        .frame(width: 160, height: 240)
        .cardHoverChrome(radius: AppTheme.Radius.medium, isHovered: isHovered, suppressEffects: isFastScrolling)
        .scaleEffect(AppThemeCoordinator.isReducingVisualEffects ? 1 : (isHovered ? 1.03 : 1.0))
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onHover { isHovered = $0 }
        .onChange(of: isFastScrolling) { _, fast in
            if fast { isHovered = false }
        }
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var posterImage: some View {
        if let posterURL = item.posterURL, let url = URL(string: posterURL) {
            CachedImage(url: url, targetSize: CGSize(width: 160, height: 240), isFastScrolling: isFastScrolling) { _ in
            } placeholder: {
                Color.secondary.opacity(0.1)
            }
            .scaledToFill()
        } else {
            ZStack {
                Color.secondary.opacity(0.1)
                Image(systemName: item.type == .movie ? "film" : "tv")
                    .foregroundStyle(AppTheme.Colors.accent)
                    .font(AppTheme.Font.title2)
            }
        }
    }
}
