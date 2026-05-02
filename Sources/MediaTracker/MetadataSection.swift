import SwiftUI
import SwiftData

struct MetadataSection: View {
    let item: MediaItem
    let themeColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let movie = item.movieDetails {
                HStack(spacing: 8) {
                    if let date = item.releaseDate {
                        MetadataLine(label: "Release Date", value: date.formatted(date: .long, time: .omitted), themeColor: themeColor)
                    }
                    if let lang = movie.originalLanguage {
                        MetadataLine(label: "Language", value: lang, themeColor: themeColor, isLanguage: true)
                    }
                }
                HStack(spacing: 8) {
                    MetadataLine(label: "Genres", value: movie.genres.joined(separator: ", "), themeColor: themeColor)
                    MetadataLine(label: "Runtime", value: DateUtils.formatRuntime(movie.runtime), themeColor: themeColor)
                }
            }

            if let tv = item.tvShowDetails {
                HStack(spacing: 8) {
                    MetadataLine(label: "Status", value: tv.status, themeColor: themeColor)
                    MetadataLine(label: "Network", value: tv.network, themeColor: themeColor)
                    if let lang = tv.originalLanguage {
                        MetadataLine(label: "Language", value: lang, themeColor: themeColor, isLanguage: true)
                    }
                }
                HStack(spacing: 8) {
                    MetadataLine(label: "Genres", value: tv.genres.joined(separator: ", "), themeColor: themeColor)
                    if let s = tv.numberOfSeasons, let e = tv.numberOfEpisodes {
                        let sLabel = s == 1 ? "Season" : "Seasons"
                        let eLabel = e == 1 ? "Episode" : "Episodes"
                        MetadataLine(label: "Library", value: "\(s) \(sLabel), \(e) \(eLabel)", themeColor: themeColor)
                    }
                }
            }
        }
    }
}
