import SwiftUI
import AppKit
import SwiftData

/// Export-only representation of a featured title. Poster pixels are resolved
/// before this view is rendered so a synchronous `ImageRenderer` never exports
/// an asynchronous image placeholder.
struct YearReviewShareHighlight: Identifiable {
    let id: PersistentIdentifier
    let title: String
    let posterImage: CGImage?
}

/// A focused, portrait recap designed to remain legible in a message preview.
/// It deliberately presents one headline, three support stats, ten personal
/// picks, and one memorable highlight instead of reproducing the dashboard.
struct YearReviewShareCardView: View {
    static let cardSize = CGSize(width: 480, height: 820)

    let review: YearInReview
    let highlights: [YearReviewShareHighlight]

    private var accent: Color { AppTheme.Colors.accent }

    private var watchTime: String {
        let hours = review.totalMinutes / 60
        if hours > 0 { return "\(hours) hours" }
        return "\(review.totalMinutes) min"
    }

    var body: some View {
        ZStack {
            Color.black

            RadialGradient(
                colors: [accent.opacity(0.28), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 370
            )

            VStack(spacing: AppTheme.Spacing.large) {
                header
                watchTimeHeadline
                supportStats
                favoriteTitles
                footer
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.vertical, AppTheme.Spacing.xLarge)
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .stroke(accent.opacity(0.45), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("MEDIATRACKER")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(AppTheme.Kerning.wide)
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            Text(String(review.year))
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(accent)
        }
    }

    private var watchTimeHeadline: some View {
        VStack(spacing: AppTheme.Spacing.micro) {
            Text("MY YEAR IN MEDIA")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(AppTheme.Kerning.wide)
                .foregroundStyle(.white.opacity(0.65))

            Text(watchTime)
                .font(.system(size: 54, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(.white)

            Text("watched")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.small)
    }

    private var supportStats: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            supportStat(value: "\(review.totalSeries)", label: "Series", icon: "tv.fill")
            supportStat(value: "\(review.totalMovies)", label: "Movies", icon: "film.fill")
            supportStat(value: review.totalEpisodes.formatted(), label: "Episodes", icon: "rectangle.stack.fill")
        }
    }

    private func supportStat(value: String, label: String, icon: String) -> some View {
        VStack(spacing: AppTheme.Spacing.micro) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
            Text(value)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .kerning(AppTheme.Kerning.tight)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, minHeight: 82)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
    }

    private var favoriteTitles: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("MY TOP 10")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .kerning(AppTheme.Kerning.wide)
                .foregroundStyle(.white.opacity(0.65))

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.small), count: 4),
                spacing: AppTheme.Spacing.small
            ) {
                ForEach(highlights.prefix(8)) { highlight in
                    poster(for: highlight)
                }

                ForEach(0..<max(0, 8 - highlights.count), id: \.self) { _ in
                    emptyHighlight
                }
            }

            if !textHighlights.isEmpty {
                HStack(spacing: AppTheme.Spacing.tiny) {
                    ForEach(textHighlights) { highlight in
                        Text(highlight.title)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .padding(.horizontal, AppTheme.Spacing.tiny)
                            .padding(.vertical, AppTheme.Spacing.mini)
                            .background(.white.opacity(0.07), in: Capsule())
                    }
                }
            }
        }
    }

    private var textHighlights: [YearReviewShareHighlight] {
        Array(highlights.dropFirst(8).prefix(2))
    }

    private func poster(for highlight: YearReviewShareHighlight) -> some View {
        Group {
            if let image = highlight.posterImage {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                emptyPoster
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
    }

    private var emptyHighlight: some View {
        emptyPoster
            .frame(maxWidth: .infinity)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
    }

    private var emptyPoster: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
            .fill(.white.opacity(0.07))
            .overlay {
                Image(systemName: "film")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(accent.opacity(0.6))
            }
    }

    private var footer: some View {
        HStack {
            Text("\(review.totalDaysWatched) ACTIVE DAYS")
            Spacer()
            Text("TRACKED WITH MEDIATRACKER")
        }
        .font(.system(size: 8, weight: .bold, design: .monospaced))
        .kerning(AppTheme.Kerning.tight)
        .foregroundStyle(.white.opacity(0.4))
    }

    @MainActor
    func renderToImage() -> NSImage? {
        renderToNSImage(width: Self.cardSize.width, height: Self.cardSize.height)
    }
}
