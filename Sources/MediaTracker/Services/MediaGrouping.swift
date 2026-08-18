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
                    return rawNetwork.commaSeparatedValues.first ?? "Unknown"
                }
                return "Unknown"
            case .year: return item.releaseDate.flatMap { Calendar.current.dateComponents([.year], from: $0).year.map { String($0) } } ?? "Unknown"
            case .category: return item.stateValue
            case .watchProvider: return item.cachedWatchProviders.first ?? "None"
            case .dayOfWeek:
                guard let releaseDate = item.releaseDate else { return "Unknown" }
                return DateUtils.weekdayDisplayString(for: releaseDate)
            case .none: return ""
            }
        }

        let grouped = dict.map { ($0.key, $0.value.map { toMetadata($0) }) }

        if groupBy == .dayOfWeek {
            return grouped.sorted { lhs, rhs in
                let lhsDate = DateUtils.weekdayDisplayDate(for: lhs.0)
                let rhsDate = DateUtils.weekdayDisplayDate(for: rhs.0)
                if lhsDate == rhsDate { return lhs.0 < rhs.0 }
                return lhsDate < rhsDate
            }
        }

        return grouped.sorted { $0.0 < $1.0 }
    }
}
