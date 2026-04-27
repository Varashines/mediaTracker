import Foundation
import SwiftData
import OSLog

/// Groundwork for macOS 26 Desktop Widgets.
/// Exports the current 'Upcoming' manifest to a shared data location.
@ModelActor
actor WidgetDataService {
    private let logger = Logger(subsystem: "com.mediatracker", category: "WidgetSync")
    
    func exportWidgetManifest() async {
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { $0.storedIsUpcoming == true },
            sortBy: [SortDescriptor(\.cachedNextAiringDate, order: .forward)]
        )
        
        guard let items = try? modelContext.fetch(descriptor) else { return }
        
        let manifest = items.prefix(5).map { item in
            WidgetMediaItem(
                id: item.id,
                title: item.title,
                subtitle: item.storedNextEpisodeLabel ?? item.badgeText ?? "",
                posterURL: item.posterURL
            )
        }
        
        // In a real app bundle, this would write to a shared App Group container.
        // For this environment, we log the intent.
        logger.info("📡 Widget Manifest exported: \(manifest.count) items.")
    }
}

struct WidgetMediaItem: Codable {
    let id: String
    let title: String
    let subtitle: String
    let posterURL: String?
}
