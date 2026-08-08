import SwiftUI

struct TrendingPosterCard: View, Equatable {
    let item: MediaSearchResult
    var isFastScrolling: Bool = false
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    
    nonisolated static func == (lhs: TrendingPosterCard, rhs: TrendingPosterCard) -> Bool {
        lhs.item.id == rhs.item.id && lhs.isFastScrolling == rhs.isFastScrolling
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            posterImage
                .frame(width: 160, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))

            if isHovered {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.5)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))

                Image(systemName: "plus.circle.fill")
                    .font(AppTheme.Font.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .padding(12)
                    .transition(.opacity)

                Text(item.title)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
            }
        }
        .frame(width: 160, height: 240)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .shadow(color: AppTheme.Colors.shadowAmbient(for: colorScheme), radius: isHovered ? 8 : 4, y: isHovered ? 4 : 2)
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
                    .shimmering()
            }
            .scaledToFill()
        } else {
            ZStack {
                Color.secondary.opacity(0.1)
                    .shimmering()
                    Image(systemName: item.type == .movie ? "film" : "tv")
                        .foregroundStyle(AppTheme.Colors.accent)
                        .font(AppTheme.Font.title2)
            }
        }
    }
}
