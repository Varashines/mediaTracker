import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

@main
struct MediaTrackerApp: App {
    // Keep a strong reference to the manager to ensure the delegate stays active
    private let notificationManager = NotificationManager.shared
    @AppStorage("theme_preference") private var themePreference: Int = 0
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self,
            NetworkEntity.self, GenreEntity.self, LanguageEntity.self, BadgeEntity.self, PersonImageEntity.self,
            StudioAliasEntity.self, SearchCacheEntity.self, MediaCollection.self
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .none
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            AppLogger.error("SwiftData migration failed, attempting store recovery: \(error)")
            
            // Attempt recovery: delete corrupted store and recreate
            let storeURL = modelConfiguration.url
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
            
            do {
                AppLogger.info("Store deleted, recreating ModelContainer...")
                return try ModelContainer(
                    for: schema,
                    configurations: [modelConfiguration]
                )
            } catch {
                fatalError("CRITICAL: Failed to initialize SwiftData ModelContainer even after store recovery. Error: \(error)")
            }
        }
    }()
    
    init() {
        // Hand off container for background actions
        NotificationManager.shared.setModelContainer(sharedModelContainer)
        
        // Hand off container for foreground and background watch sync actions
        DataService.shared.setModelContainer(sharedModelContainer)
        
        // Initialize Theme Cache
        NetworkThemeManager.shared.setup(with: sharedModelContainer)
        
        // Schedule Background Tasks
        BackgroundTaskManager.shared.start(container: sharedModelContainer)
        
        // Configure a lightweight cache for images (10MB memory, 500MB disk)
        let cacheSizeMemory = 10 * 1024 * 1024
        let cacheSizeDisk = 500 * 1024 * 1024
        let cache = URLCache(memoryCapacity: cacheSizeMemory, diskCapacity: cacheSizeDisk, directory: nil)
        URLCache.shared = cache
    }
    
    @Environment(\.scenePhase) private var scenePhase
    @State private var errorState = AppErrorState.shared

    var body: some Scene {
        WindowGroup {
            appMainContent
        }
        .modelContainer(sharedModelContainer)

        Settings {
            settingsContent
        }
    }

    @ViewBuilder
    private var appMainContent: some View {
        ContentView()
            .environment(\.sleepManager, SleepManager.shared)
            .sleepModeSupport()
            .preferredColorScheme(mappedScheme)
            .appErrorToast(state: errorState)
            .onAppear { applyTheme(themePreference) }
            .onChange(of: themePreference) { _, newPref in applyTheme(newPref) }
            .onChange(of: scenePhase) { _, newValue in
                if newValue == .background {
                    ImageCache.shared.clearMemoryCache()
                } else if newValue == .active {
                    Task {
                        await BackgroundTaskManager.shared.refreshStaleBadges()
                    }
                }
            }
    }

    @ViewBuilder
    private var settingsContent: some View {
        SettingsView()
            .modelContainer(sharedModelContainer)
            .preferredColorScheme(mappedScheme)
            .onAppear { applyTheme(themePreference) }
            .onChange(of: themePreference) { _, newPref in applyTheme(newPref) }
    }
    private var mappedScheme: ColorScheme? {
        switch themePreference {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    private func applyTheme(_ preference: Int) {
        #if os(macOS)
        // Surgical Force: Directly update the application's appearance property.
        // This ensures the window frame, title bar, and background layers
        // instantly react to theme changes without requiring window focus changes.
        DispatchQueue.main.async {
            let appearance = {
                switch preference {
                case 1: return NSAppearance(named: .aqua)
                case 2: return NSAppearance(named: .darkAqua)
                default: return nil
                }
            }()
            
            NSApp.appearance = appearance
            for window in NSApp.windows {
                window.appearance = appearance
            }
        }
        #endif
    }
}
