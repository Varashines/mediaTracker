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

    @State private var isHovered = false

    nonisolated static func == (lhs: ContinueWatchingBackdropCard, rhs: ContinueWatchingBackdropCard) -> Bool {
        lhs.metadata == rhs.metadata && lhs.isFastScrolling == rhs.isFastScrolling
    }

    private let cardWidth: CGFloat = 288
    private let cardHeight: CGFloat = 162

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
                }
                Spacer()
            }
            .padding(10)

            // Bottom info: logo (or title) + episode/genre
            VStack(alignment: .leading, spacing: 4) {
                titleLayer

                if let detailLine {
                    Text(detailLine)
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(width: cardWidth, height: cardHeight)
        .cardHoverChrome(radius: AppTheme.Radius.appleTV, isHovered: isHovered)
        .scaleEffect(AppThemeCoordinator.isReducingVisualEffects ? 1 : (isHovered ? 1.015 : 1.0))
        .if(!AppThemeCoordinator.isReducingVisualEffects) {
            $0.animation(.easeInOut(duration: 0.14), value: isHovered)
        }
        .onHover { isHovered = $0 }
        .onChange(of: isFastScrolling) { _, fast in
            if fast { isHovered = false }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var artLayer: some View {
        if let backdrop = metadata.cardBackdropURL, let url = URL(string: backdrop) {
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
        // Continue Watching always shows logos (ignores the global
        // `use_title_logos` toggle) — the backdrop art carries no title.
        if let logo = metadata.logoURL, let url = URL(string: logo) {
            CachedImage(url: url, targetSize: CGSize(width: 780, height: 185), priority: .low) {
                titleText
            }
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 190, maxHeight: 38, alignment: .leading)
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(metadata.title)
            .font(AppTheme.Font.subtitle)
            .foregroundStyle(.white)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }

    private var detailLine: String? {
        if metadata.type == .tvShow {
            // TV: episode label + top genre + runtime, no year. ("S2 E8 · Thriller · 42m")
            var parts: [String] = []
            if let ep = metadata.nextEpisodeToWatchLabel { parts.append(ep) }
            if let genre = metadata.genres.first { parts.append(genre) }
            if let runtime = metadata.runtimeMinutes, runtime > 0 { parts.append("\(runtime)m") }
            if !parts.isEmpty { return parts.joined(separator: " · ") }
            return nil
        }
        // Movies: year + genre + runtime. ("2024 · Action · 2h 9m")
        var parts = [metadata.formattedMetadata].filter { !$0.isEmpty }
        if let runtime = metadata.runtimeMinutes, runtime > 0 {
            parts.append(formatMovieRuntime(runtime))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func formatMovieRuntime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 { return "\(hours)h \(remainder)m" }
        return "\(minutes)m"
    }

    private var accessibilityLabel: String {
        var parts = [metadata.title]
        if let detailLine { parts.append(detailLine) }
        return parts.joined(separator: ", ")
    }
}
