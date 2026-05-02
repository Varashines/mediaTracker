import SwiftUI
import SwiftData

struct MetadataSection: View {
    let item: MediaItem
    let themeColor: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if let movie = item.movieDetails {
                    if let date = item.releaseDate {
                        MetadataLine(icon: "calendar", value: date.formatted(.dateTime.year().month().day()), themeColor: themeColor)
                    }
                    if let lang = movie.originalLanguage {
                        MetadataLine(icon: "globe", value: lang, themeColor: themeColor, isLanguage: true)
                    }
                    MetadataLine(icon: "clock", value: DateUtils.formatRuntime(movie.runtime), themeColor: themeColor)
                    if !movie.genres.isEmpty {
                        MetadataLine(icon: "tag.fill", value: movie.genres.joined(separator: ", "), themeColor: themeColor)
                    }
                }

                if let tv = item.tvShowDetails {
                    MetadataLine(icon: "info.circle.fill", value: tv.status, themeColor: themeColor)
                    if let net = tv.network {
                        MetadataLine(icon: "tv", value: net, themeColor: themeColor)
                    }
                    if let lang = tv.originalLanguage {
                        MetadataLine(icon: "globe", value: lang, themeColor: themeColor, isLanguage: true)
                    }
                    if !tv.genres.isEmpty {
                        MetadataLine(icon: "tag.fill", value: tv.genres.joined(separator: ", "), themeColor: themeColor)
                    }
                    if let s = tv.numberOfSeasons, let e = tv.numberOfEpisodes {
                        MetadataLine(icon: "rectangle.stack.fill", value: "\(s) Seasons, \(e) Episodes", themeColor: themeColor)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
