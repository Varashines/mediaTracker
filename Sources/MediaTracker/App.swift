import SwiftUI
import SwiftData
import Combine
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
            let timestamp = Int(Date().timeIntervalSince1970)
            let backupName = "default_corrupted_\(timestamp).store"
            let backupURL = storeURL.deletingLastPathComponent().appendingPathComponent(backupName)
            let logURL = backupURL.deletingPathExtension().appendingPathExtension("recovery.log")

            // 1. Backup the corrupted store before deletion. Surface failures to a recovery log
            //    so we never silently destroy user data on a permission/disk error.
            var backupSucceeded = true
            do {
                try FileManager.default.copyItem(at: storeURL, to: backupURL)
            } catch {
                backupSucceeded = false
                try? "store copy failed: \(error)".write(to: logURL, atomically: true, encoding: .utf8)
                AppLogger.error("📦 Failed to back up corrupted store: \(error)")
            }
            if backupSucceeded {
                let wal = storeURL.appendingPathExtension("wal")
                let shm = storeURL.appendingPathExtension("shm")
                try? FileManager.default.copyItem(at: wal, to: backupURL.appendingPathExtension("wal"))
                try? FileManager.default.copyItem(at: shm, to: backupURL.appendingPathExtension("shm"))
                AppLogger.error("📦 Corrupted store backed up to: \(backupURL.path)")
            }

            // 2. Only delete if backup succeeded; otherwise bail to fatalError with context.
            if backupSucceeded {
                try? FileManager.default.removeItem(at: storeURL)
                try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
                try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
            } else {
                try? "store recovery aborted: backup failed; refusing to delete original store".write(
                    to: logURL, atomically: true, encoding: .utf8
                )
                fatalError("CRITICAL: Corrupted store could not be backed up; refusing to delete it. See \(logURL.path). Error: \(error)")
            }

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

        let cacheSizeMemory = 10 * 1024 * 1024
        let cacheSizeDisk = 500 * 1024 * 1024
        let cache = URLCache(memoryCapacity: cacheSizeMemory, diskCapacity: cacheSizeDisk, directory: nil)
        URLCache.shared = cache

        Task { await NotificationManager.shared.requestPermission() }
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
