import SwiftUI
import SwiftData

struct MetadataSection: View {
    let item: MediaItem
    let themeColor: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
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
                    // TV Specifics: Use cached network and status from metadata if possible
                    // For now, we still check tvShowDetails for status/episodes but we'll try to minimize it
                    if let tv = item.tvShowDetails {
                        MetadataLine(icon: "info.circle.fill", value: tv.status, themeColor: themeColor)
                    }
                }

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
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
