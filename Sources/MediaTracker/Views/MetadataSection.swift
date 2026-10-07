import SwiftUI
import SwiftData

struct MetadataSection: View {
    let item: MediaItem
    let themeColor: Color
    
    @Environment(\.colorScheme) var colorScheme

    var voteAverage: Double? {
        if item.type == .movie {
            return item.movieDetails?.voteAverage
        } else {
            return item.tvShowDetails?.voteAverage
        }
    }

    private var accent: Color {
        themeColor.highContrastAccent(colorScheme: colorScheme)
    }

    private var providerStatus: String? {
        let status = item.type == .movie ? item.movieDetails?.status : item.tvShowDetails?.status
        guard let status, !status.isEmpty else { return nil }
        return status
    }

    var body: some View {
        // Genres moved to the synopsis popup, below the title, so the header is a
        // single metadata row.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppTheme.Spacing.small) { metadataPills }
            FlowLayout(spacing: AppTheme.Spacing.small) { metadataPills }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private var metadataPills: some View {
        if let providerStatus {
            infoPill(text: providerStatus, icon: "dot.radiowaves.left.and.right", accent: accent)
        }
        if let rating = voteAverage, rating > 0 {
            scoreBadge(label: "TMDB", value: String(format: "%.1f", rating), icon: "star.fill", tintColor: ratingColor(for: rating))
        }
        if let imdb = item.movieDetails?.imdbRating ?? item.tvShowDetails?.imdbRating, imdb > 0 {
            scoreBadge(label: "IMDb", value: String(format: "%.1f", imdb), icon: nil, tintColor: Color(red: 0.96, green: 0.77, blue: 0.19))
        }
        if let rt = item.movieDetails?.rottenTomatoesScore ?? item.tvShowDetails?.rottenTomatoesScore, rt > 0 {
            let isFresh = rt >= 60
            let rtColor = isFresh ? Color.semanticGreen(for: colorScheme) : Color.red
            scoreBadge(label: "RT", value: "\(rt)%", icon: isFresh ? "checkmark.seal.fill" : "exclamationmark.triangle.fill", tintColor: rtColor)
        }
        if item.type == .tvShow, let net = item.cachedNetwork, !net.isEmpty {
            infoPill(text: net, accent: accent)
        }
        if let date = item.releaseDate {
            infoPill(text: date.formatted(date: .abbreviated, time: .omitted), icon: "calendar", accent: accent)
        }
        if item.type == .movie, let runtime = item.cachedRuntime, runtime > 0 {
            infoPill(text: DateUtils.formatRuntime(runtime), icon: "clock.fill", accent: accent)
        }
        if let lang = item.cachedLanguage, !lang.isEmpty {
            infoPill(text: LanguageUtils.languageName(for: lang), icon: "globe", accent: accent)
        }
    }

    private func ratingColor(for rating: Double) -> Color {
        if rating >= 7.0 { return Color.semanticGold(for: colorScheme) }
        if rating >= 5.0 { return .yellow }
        return .red
    }

    @ViewBuilder
    private func scoreBadge(label: String, value: String, icon: String?, tintColor: Color) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9.5, weight: .black, design: .rounded))
                .foregroundStyle(tintColor)
                .opacity(0.9)

            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tintColor)
            }

            Text(value)
                .font(AppTheme.Font.bodyBold.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(tintColor.opacity(colorScheme == .dark ? 0.16 : 0.12))
        }
        .overlay {
            Capsule()
                .stroke(tintColor.opacity(colorScheme == .dark ? 0.35 : 0.28), lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private func infoPill(text: String, icon: String? = nil, accent: Color) -> some View {
        HStack(spacing: 4.5) {
            if let icon {
                Image(systemName: icon)
                    .font(AppTheme.Font.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(text)
                .font(AppTheme.Font.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.vertical, AppTheme.Spacing.micro)
        .background(
            Capsule()
                .fill(AppTheme.Colors.surfaceGhost(for: colorScheme))
                .overlay(
                    Capsule()
                        .stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 0.5)
                )
        )
    }
}
