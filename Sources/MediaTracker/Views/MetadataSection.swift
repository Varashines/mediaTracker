import SwiftUI
import SwiftData

struct MetadataSection: View {
    let item: MediaItem
    let themeColor: Color
    let watchProviders: [WatchProviderResult]
    
    @Environment(\.colorScheme) var colorScheme
    @State private var showAllGenres = false

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

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            // Row 1: All metadata pills — single line when it fits, wrapping flow otherwise
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.small) { metadataPills }
                FlowLayout(spacing: AppTheme.Spacing.small) { metadataPills }
            }

            // Row 2: Genres (pills)
            if !item.cachedGenres.isEmpty {
                let genres = item.cachedGenres
                let displayGenres = showAllGenres ? genres : Array(genres.prefix(5))
                let extraCount = genres.count - 5

                HStack(spacing: AppTheme.Spacing.small) {
                    ForEach(displayGenres, id: \.self) { genre in
                        Text(genre)
                            .font(AppTheme.Font.caption2)
                            .foregroundStyle(accent)
                            .padding(.horizontal, AppTheme.Spacing.small)
                            .padding(.vertical, AppTheme.Spacing.micro)
                            .background(
                                Capsule()
                                    .fill(accent.opacity(colorScheme == .dark ? 0.10 : 0.12))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(accent.opacity(0.15), lineWidth: 0.5)
                            )
                    }

                    if extraCount > 0 && !showAllGenres {
                        Button {
                            withAnimation(AppTheme.Animation.springSnappy) {
                                showAllGenres = true
                            }
                        } label: {
                            Text("+\(extraCount)")
                                .font(AppTheme.Font.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private var metadataPills: some View {
        if let rating = voteAverage, rating > 0 {
            ratingPill(icon: "star.fill", value: String(format: "%.1f", rating), color: ratingColor(for: rating), accent: accent)
        }
        if let rt = item.movieDetails?.rottenTomatoesScore ?? item.tvShowDetails?.rottenTomatoesScore, rt > 0 {
            let rtIcon = rt >= 60 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
            let rtColor: Color = rt >= 60 ? .green : .red
            ratingPill(icon: rtIcon, value: "\(rt)%", color: rtColor, accent: accent)
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
        if rating >= 7 { return Color.semanticGold(for: colorScheme) }
        if rating >= 5 { return .yellow }
        return .red
    }

    @ViewBuilder
    private func ratingPill(icon: String, value: String, color: Color, accent: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(AppTheme.Font.caption2)
                .foregroundStyle(color)
            Text(value)
                .font(AppTheme.Font.bodyBold.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.12))
        }
        .overlay {
            Capsule()
                .stroke(color.opacity(0.25), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func infoPill(text: String, icon: String? = nil, accent: Color) -> some View {
        HStack(spacing: 4) {
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
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(.quaternary, lineWidth: 0.5)
                )
        )
    }
}
