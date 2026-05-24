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
                items.append(MetadataItem(icon: "play.fill", value: "\(e) \(e == 1 ? "Ep" : "Eps")"))
            }
        }
        
        if item.type == .tvShow, let net = item.cachedNetwork, !net.isEmpty {
            items.append(MetadataItem(icon: "tv.fill", value: net))
        }
        
        if let lang = item.cachedLanguage, !lang.isEmpty {
            items.append(MetadataItem(icon: "globe", value: LanguageUtils.languageName(for: lang)))
        }
        
        if let firstGenre = item.cachedGenres.first {
            items.append(MetadataItem(icon: "tag.fill", value: firstGenre))
        }
        
        return items
    }

    var body: some View {
        let items = metadataItems
        HStack(spacing: 8) {
            ForEach(0..<items.count, id: \.self) { index in
                let item = items[index]
                HStack(spacing: 4) {
                    Image(systemName: item.icon)
                        .font(AppTheme.Font.caption2)
                        .foregroundStyle(themeColor.highContrastAccent(colorScheme: colorScheme))
                    Text(item.value)
                        .foregroundStyle(.primary)
                }
                .font(AppTheme.Font.caption)
                
                if index < items.count - 1 {
                    Text("·")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
        }
        .padding(.vertical, 4)
    }
}
