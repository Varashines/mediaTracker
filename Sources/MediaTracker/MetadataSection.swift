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
        
        if let date = item.releaseDate {
            let year = Calendar.current.component(.year, from: date)
            items.append(MetadataItem(icon: "calendar", value: String(year)))
        }
        
        if item.type == .movie {
            if let runtime = item.cachedRuntime, runtime > 0 {
                items.append(MetadataItem(icon: "clock.fill", value: DateUtils.formatRuntime(runtime)))
            }
        } else if item.type == .tvShow, let tv = item.tvShowDetails {
            if let s = tv.numberOfSeasons, s > 0 {
                items.append(MetadataItem(icon: "rectangle.stack.fill", value: "\(s) \(s == 1 ? "Season" : "Seasons")"))
            }
            if let e = tv.numberOfEpisodes, e > 0 {
                items.append(MetadataItem(icon: "play.fill", value: "\(e) \(e == 1 ? "Episode" : "Episodes")"))
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
        let items = metadataItems
        let mid = min(4, items.count)
        let firstRow = Array(items.prefix(mid))
        let secondRow = Array(items.suffix(from: mid))
        let accent = themeColor.highContrastAccent(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ForEach(firstRow) { meta in
                    pillView(meta, accent: accent)
                }
            }

            if !secondRow.isEmpty {
                HStack(spacing: 10) {
                    ForEach(secondRow) { meta in
                        pillView(meta, accent: accent)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func pillView(_ meta: MetadataItem, accent: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: meta.icon)
                .font(.system(size: 9))
                .foregroundStyle(accent)
            Text(meta.value)
                .font(.system(size: 11, weight: .medium, design: .rounded))
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
        .clipShape(Capsule())
    }
}
