import SwiftUI

/// Apple TV-style landscape card for Continue Watching.
///
/// Art priority: backdrop → center-cropped poster → theme-color gradient.
/// Title priority: title logo (`metadata.logoURL`, honoring `use_title_logos`)
/// → plain title text. Progress + episode label are always visible so the
/// card reads without hover.
struct ContinueWatchingBackdropCard: View, Equatable {
    let metadata: MediaThumbnailMetadata
    var isFastScrolling: Bool = false

    @AppStorage("use_title_logos") private var useTitleLogos = true
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    nonisolated static func == (lhs: ContinueWatchingBackdropCard, rhs: ContinueWatchingBackdropCard) -> Bool {
        lhs.metadata == rhs.metadata && lhs.isFastScrolling == rhs.isFastScrolling
    }

    private let cardWidth: CGFloat = 360
    private let cardHeight: CGFloat = 202

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artLayer

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Top badges
            VStack {
                HStack {
                    SmartBadgeView(metadata: metadata)
                    Spacer()
                    typeBadge
                }
                Spacer()
            }
            .padding(10)

            // Bottom info: logo (or title) + episode/progress
            VStack(alignment: .leading, spacing: 6) {
                titleLayer

                if let detailLine {
                    Text(detailLine)
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }

                if let progress = metadata.progress, progress > 0 {
                    ProgressView(value: min(max(progress, 0), 1))
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .background(.white.opacity(0.3))
                        .frame(width: 180)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
        }
        .shadow(
            color: isHovered
                ? AppTheme.Colors.shadowElevated(for: colorScheme)
                : AppTheme.Colors.shadowAmbient(for: colorScheme),
            radius: isHovered ? 10 : 5, y: isHovered ? 5 : 2
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onChange(of: isFastScrolling) { _, fast in
            if fast { isHovered = false }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var artLayer: some View {
        if let backdrop = metadata.backdropURL, let url = URL(string: backdrop) {
            CachedImage(url: url, targetSize: .backdropCompact, isFastScrolling: isFastScrolling) {
                Rectangle().fill(Color.secondary.opacity(0.12))
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: cardWidth, height: cardHeight)
            .clipped()
        } else if let poster = metadata.posterURL, let url = URL(string: poster) {
            // Center-cropped poster fallback: portrait art fills the 16:9 frame.
            CachedImage(url: url, targetSize: .thumbMedium, isFastScrolling: isFastScrolling) {
                Rectangle().fill(Color.secondary.opacity(0.12))
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: cardWidth, height: cardHeight)
            .clipped()
        } else {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            (metadata.themeColorHex.flatMap { Color(hex: $0) } ?? .gray).opacity(0.7),
                            .black.opacity(0.85),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: cardWidth, height: cardHeight)
        }
    }

    @ViewBuilder
    private var titleLayer: some View {
        if useTitleLogos, let logo = metadata.logoURL, let url = URL(string: logo) {
            CachedImage(url: url, targetSize: CGSize(width: 780, height: 185), priority: .low) {
                titleText
            }
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 220, maxHeight: 44, alignment: .leading)
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(metadata.title)
            .font(AppTheme.Font.title3)
            .foregroundStyle(.white)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }

    private var detailLine: String? {
        var parts: [String] = []
        if let ep = metadata.nextEpisodeToWatchLabel { parts.append(ep) }
        if let wp = metadata.watchProgress { parts.append(wp) }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        let fallback = metadata.formattedMetadata
        return fallback.isEmpty ? nil : fallback
    }

    @ViewBuilder
    private var typeBadge: some View {
        if let type = metadata.type {
            Group {
                switch type {
                case .movie: Image(systemName: "film.fill")
                case .tvShow: Image(systemName: "tv.fill")
                }
            }
            .font(AppTheme.Icon.small)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(.white)
            .background { Capsule().fill(Color.black.opacity(0.7)) }
            .overlay { Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5) }
            .clipShape(Capsule())
        }
    }

    private var accessibilityLabel: String {
        var parts = [metadata.title]
        if let detailLine { parts.append(detailLine) }
        return parts.joined(separator: ", ")
    }
}
