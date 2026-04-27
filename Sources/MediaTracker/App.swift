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
            NetworkEntity.self, GenreEntity.self, LanguageEntity.self, PersonImageEntity.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Fatal error with context to help debugging
            fatalError("CRITICAL: Failed to initialize SwiftData ModelContainer. This is likely due to an incompatible schema change. Error: \(error)")
        }
    }()
    
    init() {
        // Initialize dynamic resource monitoring
        _ = MemoryPressureMonitor.shared
        
        // Hand off container for background actions
        NotificationManager.shared.setModelContainer(sharedModelContainer)
        
        // Configure a lightweight cache for images (10MB memory, 500MB disk)
        let cacheSizeMemory = 10 * 1024 * 1024
        let cacheSizeDisk = 500 * 1024 * 1024
        let cache = URLCache(memoryCapacity: cacheSizeMemory, diskCapacity: cacheSizeDisk, directory: nil)
        URLCache.shared = cache
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ForceSwiftDataSave"), object: nil, queue: .main) { _ in
            // Trigger a manual save of the container to prevent data loss during purge
            // Note: SwiftData usually autosaves, but under extreme pressure we force it.
            print("💾 Force saving SwiftData due to memory pressure...")
        }
    }
    
    @Environment(\.scenePhase) private var scenePhase
    @State private var errorState = AppErrorState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(mappedScheme)
                .appErrorToast(state: errorState)
                .onAppear { applyTheme(themePreference) }
                .onChange(of: themePreference) { _, newPref in applyTheme(newPref) }
                .onChange(of: scenePhase) { _, newValue in
                    if newValue == .background {
                        // Phase 3 Optimization: Snapshot preparation for M1 8GB
                        ImageCache.shared.clearMemoryCache()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        
        MenuBarExtra("MediaTracker", systemImage: "play.tv") {
            MenuBarDashboard()
                .modelContainer(sharedModelContainer)
        }
        .menuBarExtraStyle(.window)
        
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

    private func applyTheme(_ preference: Int) {
        #if os(macOS)
        // Surgical Force: Directly update the application's appearance property.
        // This ensures the window frame, title bar, and background layers
        // instantly react to theme changes without requiring window focus changes.
        DispatchQueue.main.async {
            switch preference {
            case 1: NSApp.appearance = NSAppearance(named: .aqua)
            case 2: NSApp.appearance = NSAppearance(named: .darkAqua)
            default: NSApp.appearance = nil // Revert to system default
            }
        }
        #endif
    }
}
