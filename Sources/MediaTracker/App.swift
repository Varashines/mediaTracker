import SwiftUI
import SwiftData
import Combine
#if os(macOS)
import AppKit
#endif

@main
struct MediaTrackerApp: App {
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
        NotificationManager.shared.setModelContainer(sharedModelContainer)
        DataService.shared.setModelContainer(sharedModelContainer)
        NetworkThemeManager.shared.setup(with: sharedModelContainer)
        BackgroundTaskManager.shared.start(container: sharedModelContainer)

        let cacheSizeMemory = 10 * 1024 * 1024
        let cacheSizeDisk = 500 * 1024 * 1024
        let cache = URLCache(memoryCapacity: cacheSizeMemory, diskCapacity: cacheSizeDisk, directory: nil)
        URLCache.shared = cache
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var errorState = AppErrorState.shared
    @State private var systemColorScheme: ColorScheme = .light
    @State private var appearanceObserver: AnyCancellable?

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
            .onAppear {
                updateSystemColorScheme()
                observeSystemAppearance()
                applyTheme(themePreference)
            }
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
            .onAppear {
                updateSystemColorScheme()
                applyTheme(themePreference)
            }
            .onChange(of: themePreference) { _, newPref in applyTheme(newPref) }
    }

    private var mappedScheme: ColorScheme? {
        if themePreference == 3 {
            DispatchQueue.main.async {
                UserDefaults.standard.set(2, forKey: "theme_preference")
                UserDefaults.standard.set(1, forKey: "dark_theme_style")
            }
            return .dark
        }
        switch themePreference {
        case 1: return .light
        case 2: return .dark
        default: return systemColorScheme
        }
    }

    private func updateSystemColorScheme() {
        #if os(macOS)
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        systemColorScheme = isDark ? .dark : .light
        #endif
    }

    private func observeSystemAppearance() {
        #if os(macOS)
        appearanceObserver = NSApp.publisher(for: \.effectiveAppearance)
            .receive(on: RunLoop.main)
            .sink { _ in
                updateSystemColorScheme()
            }
        #endif
    }

    private func applyTheme(_ preference: Int) {
        #if os(macOS)
        let pref = preference == 3 ? 2 : preference
        let appearance = {
            switch pref {
            case 1: return NSAppearance(named: .aqua)
            case 2: return NSAppearance(named: .darkAqua)
            default: return nil
            }
        }()
        NSApp.appearance = appearance
        for window in NSApp.windows {
            window.appearance = appearance
        }
        #endif
    }
}
