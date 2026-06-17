import SwiftUI

struct TrendingPosterCard: View {
    let item: MediaSearchResult
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            posterImage
                .frame(width: 160, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))

            if isHovered {
                Color.black.opacity(0.3)
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
        .shadow(color: .black.opacity(isHovered ? 0.15 : 0), radius: 8, y: 4)
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var posterImage: some View {
        if let posterURL = item.posterURL, let url = URL(string: posterURL) {
            CachedImage(url: url, targetSize: CGSize(width: 160, height: 240)) { _ in
            } placeholder: {
                Color.secondary.opacity(0.1)
            }
            .scaledToFill()
        } else {
            ZStack {
                Color.secondary.opacity(0.1)
                Image(systemName: item.type == .movie ? "film" : "tv")
                    .foregroundStyle(.secondary)
                    .font(.title2)
            }
        }
    }
}
