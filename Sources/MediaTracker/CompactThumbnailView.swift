import SwiftUI

struct CompactThumbnailView: View {
    let metadata: MediaThumbnailMetadata
    var isFastScrolling: Bool = false
    var isCompletedInCollection: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private let cardWidth: CGFloat = 210
    private let cardHeight: CGFloat = 112

    private var themeColor: Color? {
        metadata.themeColorHex.flatMap { Color(hex: $0) }
    }

    private var stateDotColor: Color? {
        guard let state = metadata.state else { return nil }
        switch state {
        case .active, .rewatching: return .blue
        case .wishlist: return .yellow
        case .onHold: return .gray
        case .dropped: return .red
        case .completed: return nil
        }
    }

    private var yearString: String? {
        metadata.releaseDate.flatMap {
            Calendar.current.dateComponents([.year], from: $0).year.map(String.init)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            posterArea

            infoArea

            Spacer(minLength: 0)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(backgroundFill)
        .overlay(alignment: .topTrailing) {
            statusDot
        }
        .overlay(hoverGlow)
        .overlay(borderStroke)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .shadow(
            color: (themeColor ?? .black).opacity(isHovered ? 0.12 : 0.03),
            radius: isHovered ? 6 : 1.5,
            x: 0,
            y: isHovered ? 4 : 1
        )
        .scaleEffect(isHovered ? 1.03 : 1)
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: isHovered)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var posterArea: some View {
        ZStack(alignment: .topTrailing) {
            if let poster = metadata.posterURL, let url = URL(string: poster) {
                CachedImage(url: url, targetSize: .thumbSmall, isFastScrolling: isFastScrolling) {
                    Rectangle().fill(Color.secondary.opacity(0.06))
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 75, height: cardHeight)
                .clipped()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 75, height: cardHeight)
                    .overlay {
                        Image(systemName: metadata.type == .movie ? "film" : "tv")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary.opacity(0.3))
                    }
            }

            if isCompletedInCollection {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .background(
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 14, height: 14)
                    )
                    .padding(4)
                    .opacity(isHovered ? 0 : 1)
            }
        }
    }

    @ViewBuilder
    private var infoArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metadata.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .lineSpacing(2)

            HStack(spacing: 8) {
                if let year = yearString {
                    Text(year)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary)
                }

                if let firstGenre = metadata.genres.first {
                    Text(firstGenre)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var statusDot: some View {
        if let dotColor = stateDotColor {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .shadow(color: dotColor.opacity(0.3), radius: 2, y: 1)
                .padding(8)
        }
    }

    private var backgroundFill: some View {
        ZStack {
            let base = themeColor?.opacity(colorScheme == .dark ? 0.10 : 0.07) ?? Color(NSColor.windowBackgroundColor)
            RoundedRectangle(cornerRadius: 16)
                .fill(base)

            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(colorScheme == .dark ? 0.03 : 0.05),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    private var hoverGlow: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(themeColor?.opacity(isHovered ? 0.25 : 0) ?? Color.clear, lineWidth: 1.5)
    }

    private var borderStroke: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10),
                        Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}
