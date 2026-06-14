import SwiftUI
import SwiftData

struct MetadataSection: View {
    let item: MediaItem
    let themeColor: Color
    
    @Environment(\.colorScheme) var colorScheme

    struct MetadataItem: Identifiable {
        let id = UUID()
        let icon: String
        let value: String
    }

    var voteAverage: Double? {
        if item.type == .movie {
            return item.movieDetails?.voteAverage
        } else {
            return item.tvShowDetails?.voteAverage
        }
    }

    private var metadataItems: [MetadataItem] {
        var items: [MetadataItem] = []
        
        if let rating = voteAverage, rating > 0 {
            items.append(MetadataItem(icon: "star.fill", value: String(format: "%.1f", rating)))
        }
        if let rt = item.movieDetails?.rottenTomatoesScore ?? item.tvShowDetails?.rottenTomatoesScore, rt > 0 {
            let icon = rt >= 60 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
            items.append(MetadataItem(icon: icon, value: "\(rt)%"))
        }
        if let rated = item.movieDetails?.contentRating ?? item.tvShowDetails?.contentRating, !rated.isEmpty, rated != "N/A" {
            items.append(MetadataItem(icon: rated.contains("TV") ? "tv.fill" : "film.fill", value: rated))
        }
        
        if let date = item.releaseDate {
            items.append(MetadataItem(icon: "calendar", value: date.formatted(date: .abbreviated, time: .omitted)))
        }
        
        if item.type == .movie {
            if let runtime = item.cachedRuntime, runtime > 0 {
                items.append(MetadataItem(icon: "clock.fill", value: DateUtils.formatRuntime(runtime)))
            }
        } else if item.type == .tvShow, let tv = item.tvShowDetails {
            if let s = tv.numberOfSeasons, s > 0, let e = tv.numberOfEpisodes, e > 0 {
                items.append(MetadataItem(icon: "rectangle.stack.fill", value: "\(s) \(s == 1 ? "Season" : "Seasons") · \(e) EP"))
            } else if let s = tv.numberOfSeasons, s > 0 {
                items.append(MetadataItem(icon: "rectangle.stack.fill", value: "\(s) \(s == 1 ? "Season" : "Seasons")"))
            } else if let e = tv.numberOfEpisodes, e > 0 {
                items.append(MetadataItem(icon: "play.fill", value: "\(e) EP"))
            }
        }
        
        if item.type == .tvShow, let net = item.cachedNetwork, !net.isEmpty {
            items.append(MetadataItem(icon: "tv.fill", value: net))
        }
        
        if let lang = item.cachedLanguage, !lang.isEmpty {
            items.append(MetadataItem(icon: "globe", value: LanguageUtils.languageName(for: lang)))
        }
        
        for genre in item.cachedGenres {
            items.append(MetadataItem(icon: "tag.fill", value: genre))
        }
        
        return items
    }

    var body: some View {
        let accent = themeColor.highContrastAccent(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Primary info (what is this?)
            HStack(spacing: 10) {
                ForEach(firstRowItems) { meta in
                    pillView(meta, accent: accent)
                }
            }
            // Row 2: Secondary info (details)
            if !secondRowItems.isEmpty {
                HStack(spacing: 10) {
                    ForEach(secondRowItems) { meta in
                        pillView(meta, accent: accent)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var firstRowItems: [MetadataItem] {
        // Primary: status, rating, RT, content rating, date
        Array(metadataItems.prefix(5))
    }

    private var secondRowItems: [MetadataItem] {
        // Secondary: seasons/runtime, network, language, genres
        Array(metadataItems.dropFirst(5))
    }

    @ViewBuilder
    private func pillView(_ meta: MetadataItem, accent: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: meta.icon)
                .font(AppTheme.Font.small)
                .foregroundStyle(accent)
            Text(meta.value)
                .font(AppTheme.Font.caption)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(themeColor.opacity(colorScheme == .dark ? 0.10 : 0.14))
        }
        .overlay {
            Capsule()
                .stroke(themeColor.opacity(colorScheme == .dark ? 0.15 : 0.20), lineWidth: 0.5)
        }
    }
}
