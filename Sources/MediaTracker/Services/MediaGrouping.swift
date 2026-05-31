import Foundation
import SwiftData

extension MediaFilterActor {
    func groupResults(_ results: [MediaItem], groupBy: GroupBy, collectionID: UUID? = nil) -> [(String, [MediaThumbnailMetadata])] {
        if groupBy == .none { return [] }

        let dict = Dictionary(grouping: results) { item -> String in
            switch groupBy {
            case .genre: return item.cachedGenres.first ?? "Uncategorized"
            case .language: return item.cachedLanguage ?? "Unknown"
            case .network:
                if let rawNetwork = item.cachedNetwork {
                    return rawNetwork.components(separatedBy: ",").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?.trimmingCharacters(in: .whitespaces) ?? "Unknown"
                }
                return "Unknown"
            case .year: return item.releaseDate.flatMap { Calendar.current.dateComponents([.year], from: $0).year.map { String($0) } } ?? "Unknown"
            case .category: return item.stateValue
            case .none: return ""
            }
        }

        let grouped = dict.map { ($0.key, $0.value.map { toMetadata($0) }) }

        return grouped.sorted { $0.0 < $1.0 }
    }
}
