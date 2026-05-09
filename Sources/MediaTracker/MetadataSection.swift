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

                if item.type == .movie {
                    if let movie = item.movieDetails {
                        MetadataLine(icon: "clock", value: DateUtils.formatRuntime(movie.runtime), themeColor: themeColor)
                    }
                } else if item.type == .tvShow {
                    if let tv = item.tvShowDetails {
                        MetadataLine(icon: "info.circle.fill", value: tv.status, themeColor: themeColor)
                    }
                }
            }
            
            // Row 2: Origin & Content
            HStack(spacing: 12) {
                if let net = item.cachedNetwork {
                    MetadataLine(icon: "tv", value: net, themeColor: themeColor)
                }

                if !item.cachedGenres.isEmpty {
                    MetadataLine(icon: "tag.fill", value: item.cachedGenres.joined(separator: ", "), themeColor: themeColor)
                }

                if item.type == .tvShow, let tv = item.tvShowDetails {
                    if let s = tv.numberOfSeasons, let e = tv.numberOfEpisodes {
                        MetadataLine(icon: "rectangle.stack.fill", value: "\(s) Seasons, \(e) Episodes", themeColor: themeColor)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
