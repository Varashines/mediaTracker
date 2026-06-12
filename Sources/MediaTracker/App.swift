import SwiftUI
import SwiftData
import Combine
import CoreSpotlight
#if os(macOS)
import AppKit
#endif

extension Notification.Name {
    static let openSettingsTab = Notification.Name("openSettingsTab")
}

@main
struct MediaTrackerApp: App {
    private let notificationManager = NotificationManager.shared
    @AppStorage("theme_preference") private var themePreference: Int = 0
    @AppStorage("custom_theme_palette") private var customThemePalette = 0

    var sharedModelContainer: ModelContainer = {
        let schema = Schema(AppSchemaV1.models)

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .none
        )

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [modelConfiguration]
            )
        } catch {
            AppLogger.error("CRITICAL: SwiftData migration failed — backing up store before recovery: \(error)")

            let storeURL = modelConfiguration.url

            // 1. Backup the corrupted store before deletion
            let backupName = "default_corrupted_\(Int(Date().timeIntervalSince1970)).store"
            let backupURL = storeURL.deletingLastPathComponent().appendingPathComponent(backupName)
            try? FileManager.default.copyItem(at: storeURL, to: backupURL)
            try? FileManager.default.copyItem(at: storeURL.appendingPathExtension("wal"), to: backupURL.appendingPathExtension("wal"))
            try? FileManager.default.copyItem(at: storeURL.appendingPathExtension("shm"), to: backupURL.appendingPathExtension("shm"))
            AppLogger.error("📦 Corrupted store backed up to: \(backupURL.path)")

            // 2. Delete the corrupted store
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))

            do {
                AppLogger.info("Store deleted, recreating ModelContainer...")
                let container = try ModelContainer(
                    for: schema,
                    migrationPlan: AppMigrationPlan.self,
                    configurations: [modelConfiguration]
                )
                Task { @MainActor in
                    AppErrorState.shared.storeRecoveredFromMigrationFailure = true
                }
                return container
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
        SpotlightIndexService.modelContainer = sharedModelContainer

        let cacheSizeMemory = 10 * 1024 * 1024
        let cacheSizeDisk = 500 * 1024 * 1024
        let cache = URLCache(memoryCapacity: cacheSizeMemory, diskCapacity: cacheSizeDisk, directory: nil)
        URLCache.shared = cache

        Task { await NotificationManager.shared.requestPermission() }

        // Migration: Bulk re-extract poster colors with CoreImage algorithm (v4)
        let extractionVersion = UserDefaults.standard.integer(forKey: "colorExtractionVersion")
        if extractionVersion < 4 {
            let container = sharedModelContainer
            Task { @MainActor in
                let descriptor = FetchDescriptor<MediaItem>()
                guard let items = try? container.mainContext.fetch(descriptor) else { return }

                var processed = 0
                for item in items {
                    guard item.modelContext != nil, !item.isDeleted else { continue }
                    guard let poster = item.posterURL, let url = URL(string: poster) else { continue }

                    // Re-extract all items with new CoreImage algorithm
                    if let (data, _) = try? await ImageCache.shared.imageSession.data(from: url) {
                        let pair: DominantPair? = await Task.detached {
                            if let image = NSImage(data: data),
                               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                                return await ColorExtractor.topTwoColors(from: cgImage)
                            }
                            return nil
                        }.value

                        if let pair {
                            item.themeColorHex = "\(pair.primary.toHex())|\(pair.secondary.toHex())"
                            item.themeColorSourceURL = poster
                            processed += 1
                        }
                    }

                    if processed % 5 == 0 {
                        try? await Task.sleep(nanoseconds: 10_000_000)
                    }
                }

                try? container.mainContext.save()
                UserDefaults.standard.set(4, forKey: "colorExtractionVersion")
                AppLogger.info("🎨 Migration v4: Re-extracted poster colors for \(processed) items with CoreImage.", logger: AppLogger.background)
            }
        }

        // Spotlight: initial bulk indexing
        let spotContainer = sharedModelContainer
        Task { @MainActor in
            let indexVersion = UserDefaults.standard.integer(forKey: "spotlightIndexVersion")
            guard indexVersion < 1 else { return }
            let context = ModelContext(spotContainer)
            var descriptor = FetchDescriptor<MediaItem>()
            descriptor.propertiesToFetch = MediaItem.thumbnailProperties
            if let items = try? context.fetch(descriptor), !items.isEmpty {
                await SpotlightIndexService.shared.reindexAll(items)
            }
            UserDefaults.standard.set(1, forKey: "spotlightIndexVersion")
        }
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
            .tint(AppTheme.Colors.accent)
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
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
                NavigationRouter.shared.pendingSpotlightItemID = identifier
            }
            .onContinueUserActivity("com.vara.MediaTracker.viewItem") { activity in
                guard let id = activity.userInfo?["id"] as? String else { return }
                NavigationRouter.shared.pendingSpotlightItemID = id
            }
    }

    @ViewBuilder
    private var settingsContent: some View {
        SettingsView()
            .modelContainer(sharedModelContainer)
            .preferredColorScheme(mappedScheme)
            .tint(AppTheme.Colors.accent)
            .onAppear {
                updateSystemColorScheme()
                applyTheme(themePreference)
            }
            .onChange(of: themePreference) { _, newPref in applyTheme(newPref) }
    }

    private var mappedScheme: ColorScheme? {
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
        #endif
    }
}
