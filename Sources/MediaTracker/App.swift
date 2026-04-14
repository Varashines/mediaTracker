import SwiftUI
import SwiftData

@main
struct MediaTrackerApp: App {
    // Keep a strong reference to the manager to ensure the delegate stays active
    private let notificationManager = NotificationManager.shared
    
    init() {
        // Configure a large, persistent cache for images (100MB memory, 500MB disk)
        let cacheSizeMemory = 100 * 1024 * 1024
        let cacheSizeDisk = 500 * 1024 * 1024
        let cache = URLCache(memoryCapacity: cacheSizeMemory, diskCapacity: cacheSizeDisk, directory: nil)
        URLCache.shared = cache
        
        notificationManager.requestPermission()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [MediaItem.self, MovieDetails.self, TVShowDetails.self, BookDetails.self, TVSeason.self, TVEpisode.self])
        
        Settings {
            SettingsView()
        }
    }
}
