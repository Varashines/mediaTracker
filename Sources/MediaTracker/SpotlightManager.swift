import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

@MainActor
class SpotlightManager {
    static let shared = SpotlightManager()
    
    private init() {}
    
    func indexItem(_ item: MediaItem) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .content)
        attributeSet.title = item.title
        attributeSet.contentDescription = item.overview
        attributeSet.identifier = item.id
        
        // Custom attributes based on type
        if let type = item.type {
            attributeSet.genre = type.rawValue
            switch type {
            case .movie:
                attributeSet.contentModificationDate = item.releaseDate
            case .tvShow:
                if let tv = item.tvShowDetails {
                    attributeSet.information = "Status: \(tv.status ?? "Unknown")"
                }
            case .book:
                if let book = item.bookDetails {
                    attributeSet.authorNames = book.authors
                }
            }
        }
        
        // Add a unique identifier for our app's deep linking
        let searchableItem = CSSearchableItem(
            uniqueIdentifier: item.id,
            domainIdentifier: "com.vara.mediatracker",
            attributeSet: attributeSet
        )
        
        let title = item.title
        CSSearchableIndex.default().indexSearchableItems([searchableItem]) { error in
            if let error = error {
                print("❌ Spotlight indexing error: \(error.localizedDescription)")
            } else {
                print("✅ Spotlight indexed: \(title)")
            }
        }
    }
    
    func removeItem(_ item: MediaItem) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [item.id]) { error in
            if let error = error {
                print("❌ Spotlight removal error: \(error.localizedDescription)")
            }
        }
    }
    
    func indexAll(items: [MediaItem]) {
        for item in items {
            indexItem(item)
        }
    }
}
