import SwiftUI
import SwiftData

@main
struct MediaTrackerApp: App {
    // Keep a strong reference to the manager to ensure the delegate stays active
    private let notificationManager = NotificationManager.shared
    @AppStorage("theme_preference") private var themePreference: Int = 0
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    init() {
        // Configure a large, persistent cache for images (100MB memory, 500MB disk)
        let cacheSizeMemory = 100 * 1024 * 1024
        let cacheSizeDisk = 500 * 1024 * 1024
        let cache = URLCache(memoryCapacity: cacheSizeMemory, diskCapacity: cacheSizeDisk, directory: nil)
        URLCache.shared = cache
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(mappedScheme)
        }
        .modelContainer(sharedModelContainer)
        
        Settings {
            SettingsView()
                .modelContainer(sharedModelContainer)
                .preferredColorScheme(mappedScheme)
        }
    }

    private var mappedScheme: ColorScheme? {
        switch themePreference {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }
}
