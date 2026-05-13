import SwiftUI
import SwiftData

struct MetadataSection: View {
    let item: MediaItem
    let themeColor: Color

    var voteAverage: Double? {
        if item.type == .movie {
            return item.movieDetails?.voteAverage
        } else {
            return item.tvShowDetails?.voteAverage
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: Core Metadata
            HStack(spacing: 12) {
                if let rating = voteAverage, rating > 0 {
                    MetadataLine(icon: "star.fill", value: String(format: "%.1f", rating), themeColor: themeColor)
                }

                if let date = item.releaseDate {
                    MetadataLine(icon: "calendar", value: date.formatted(.dateTime.year().month().day()), themeColor: themeColor)
                }
                
                if let lang = item.cachedLanguage {
                    MetadataLine(icon: "globe", value: lang, themeColor: themeColor, isLanguage: true)
                }

                if let net = item.cachedNetwork {
                    MetadataLine(icon: "tv.fill", value: net, themeColor: themeColor)
                }
            }
            
            // Row 2: Content Details
            HStack(spacing: 12) {
                if item.type == .movie {
                    MetadataLine(icon: "clock.fill", value: DateUtils.formatRuntime(item.cachedRuntime), themeColor: themeColor)
                } else if item.type == .tvShow {
                    if let tv = item.tvShowDetails {
                        MetadataLine(icon: "info.circle.fill", value: tv.status, themeColor: themeColor)
                        
                        if let s = tv.numberOfSeasons, let e = tv.numberOfEpisodes {
                            MetadataLine(icon: "rectangle.stack.fill", value: "\(s) Seasons, \(e) Episodes", themeColor: themeColor)
                        }
                    }
                }

                if !item.cachedGenres.isEmpty {
                    MetadataLine(icon: "tag.fill", value: item.cachedGenres.joined(separator: ", "), themeColor: themeColor)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
