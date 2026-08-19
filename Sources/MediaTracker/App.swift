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
            MediaItem.self, MovieDetails.self, TVShowDetails.self,
            TVSeason.self, TVEpisode.self, CastMember.self,
            NetworkEntity.self, GenreEntity.self, LanguageEntity.self,
            BadgeEntity.self, PersonImageEntity.self,
            StudioAliasEntity.self, SearchCacheEntity.self,
            MediaCollection.self, ProviderEntity.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .none
        )

        // Check for backup files from a previous corruption recovery.
        // On the first launch after adding a backup, try to restore the oldest backup.
        // Skip validation — just restore and let the main container creation handle migration.
        // If it fails, the catch block below backs it up again and creates a fresh store.
        let storeURL = modelConfiguration.url
        let storeDir = storeURL.deletingLastPathComponent()
        let didRestoreKey = "com.vara.mediatracker.didRestoreBackup"
        if !UserDefaults.standard.bool(forKey: didRestoreKey),
           let backupFiles = try? FileManager.default.contentsOfDirectory(at: storeDir, includingPropertiesForKeys: nil) {
            // Filter: match "default_corrupted_vMAJOR_MINOR_<timestamp>.store"
            let candidates = backupFiles.filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix("default_corrupted_v") && name.hasSuffix(".store")
                    && name.dropFirst(20).contains("_")
            }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            // Check version compatibility: read the .version file written alongside the backup
            let currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
            var compatibleBackup: URL?
            for backup in candidates {
                let versionURL = backup.deletingPathExtension().appendingPathExtension("version")
                let backupVersion = (try? String(contentsOf: versionURL, encoding: .utf8)).flatMap {
                    // Backups from same major version are compatible
                    let backupMajor = $0.split(separator: ".").first ?? ""
                    let currentMajor = currentVersion.split(separator: ".").first ?? ""
                    return backupMajor == currentMajor ? $0 : nil
                }
                if backupVersion != nil {
                    compatibleBackup = backup
                    break
                }
            }
            if let backupURL = compatibleBackup {
                AppLogger.info("Found compatible backup: \(backupURL.lastPathComponent). Restoring...")
                let savedCurrent = storeDir.appendingPathComponent("default_current_saved.store")
                try? FileManager.default.removeItem(at: savedCurrent)
                try? FileManager.default.copyItem(at: storeURL, to: savedCurrent)
                try? FileManager.default.removeItem(at: storeURL)
                try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
                try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
                try? FileManager.default.copyItem(at: backupURL, to: storeURL)
                try? FileManager.default.copyItem(at: backupURL.appendingPathExtension("wal"), to: storeURL.appendingPathExtension("wal"))
                try? FileManager.default.copyItem(at: backupURL.appendingPathExtension("shm"), to: storeURL.appendingPathExtension("shm"))
            }
            UserDefaults.standard.set(true, forKey: didRestoreKey)
        }

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            let firstError = error
            AppLogger.error("CRITICAL: SwiftData migration failed — backing up store before recovery: \(firstError)")

            let storeURL = modelConfiguration.url
            let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)?.replacingOccurrences(of: ".", with: "_") ?? "unknown"
            let timestamp = Int(Date().timeIntervalSince1970)
            let backupName = "default_corrupted_v\(appVersion)_\(timestamp).store"
            let backupURL = storeURL.deletingLastPathComponent().appendingPathComponent(backupName)
            let logURL = backupURL.deletingPathExtension().appendingPathExtension("recovery.log")
            let versionURL = backupURL.deletingPathExtension().appendingPathExtension("version")

            // 1. Backup the corrupted store before deletion. Surface failures to a recovery log
            //    so we never silently destroy user data on a permission/disk error.
            var backupSucceeded = true
            do {
                try "Migration error: \(firstError)".write(to: logURL, atomically: true, encoding: .utf8)
                try appVersion.write(to: versionURL, atomically: true, encoding: .utf8)
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

            // Try to restore from backup with the new migration plan.
            // If the failure was just a schema mismatch (now fixed), this will work.
            var restoredFromBackup = false
            if backupSucceeded {
                do {
                    let backupConfig = ModelConfiguration(url: backupURL)
                    AppLogger.info("Attempting to validate backup store...")
                    let _ = try ModelContainer(
                        for: schema,
                        configurations: [backupConfig]
                    )
                    AppLogger.info("Backup validated. Restoring from backup...")
                    try FileManager.default.copyItem(at: backupURL, to: storeURL)
                    try? FileManager.default.copyItem(at: backupURL.appendingPathExtension("wal"), to: storeURL.appendingPathExtension("wal"))
                    try? FileManager.default.copyItem(at: backupURL.appendingPathExtension("shm"), to: storeURL.appendingPathExtension("shm"))
                    let container = try ModelContainer(
                        for: schema,
                        configurations: [modelConfiguration]
                    )
                    AppLogger.info("Database restored from backup.")
                    restoredFromBackup = true
                    return container
                } catch {
                    AppLogger.error("Backup restoration failed, starting fresh: \(error)")
                }
            }

            do {
                AppLogger.info("Creating fresh ModelContainer...")
                let container = try ModelContainer(
                    for: schema,
                    configurations: [modelConfiguration]
                )
                if !restoredFromBackup {
                    Task { @MainActor in
                        AppErrorState.shared.storeRecoveredFromMigrationFailure = true
                    }
                }
                return container
            } catch {
                fatalError("CRITICAL: Failed to initialize SwiftData ModelContainer even after store recovery. Error: \(error)")
            }
        }
    }()

    init() {
        KeychainStore.restoreToUserDefaults()
        NotificationManager.shared.setModelContainer(sharedModelContainer)
        DataService.shared.setModelContainer(sharedModelContainer)
        NetworkThemeManager.shared.setup(with: sharedModelContainer)
        BackgroundTaskManager.shared.start(container: sharedModelContainer)

        let cacheSizeMemory = 10 * 1024 * 1024
        let cacheSizeDisk = 500 * 1024 * 1024
        let cache = URLCache(memoryCapacity: cacheSizeMemory, diskCapacity: cacheSizeDisk, directory: nil)
        URLCache.shared = cache

        Task { await NotificationManager.shared.requestPermission() }
        Task { await NotificationManager.shared.rescheduleWeeklyDigestIfNeeded() }
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var errorState = AppErrorState.shared
    @State private var lockService = AppLockService.shared
    @State private var systemColorScheme: ColorScheme = .light
    @State private var appearanceObserver: AnyCancellable?

    var body: some Scene {
        WindowGroup {
            appMainContent
        }
        .modelContainer(sharedModelContainer)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { content, context in
            let displayBounds = context.defaultDisplay.visibleRect
            let size = content.sizeThatFits(.unspecified)
            return WindowPlacement(
                CGPoint(
                    x: displayBounds.midX - (size.width / 2),
                    y: displayBounds.midY - (size.height / 2)
                ),
                size: size
            )
        }

        Settings {
            settingsContent
        }


    }

    @ViewBuilder
    private var appMainContent: some View {
        ZStack {
            ContentView()
                .environment(\.sleepManager, SleepManager.shared)
                .sleepModeSupport()
                .blur(radius: lockService.isLocked ? 6 : 0)

            if lockService.isLocked {
                LockScreenView()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .preferredColorScheme(mappedScheme)
        .tint(AppTheme.Colors.accent)
        .sensoryFeedback(HapticTrigger.shared.feedback, trigger: HapticTrigger.shared.token)
        .appErrorToast(state: errorState)
        .onAppear {
            updateSystemColorScheme()
            observeSystemAppearance()
            applyTheme(themePreference)
            lockService.lock()
        }
        .onChange(of: themePreference) { _, newPref in applyTheme(newPref) }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .background || newValue == .inactive {
                if newValue == .background { ImageCache.shared.clearMemoryCache() }
                lockService.lock()
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
        let newScheme: ColorScheme = isDark ? .dark : .light
        if systemColorScheme != newScheme {
            systemColorScheme = newScheme
            AppThemeCoordinator.shared.appearanceDidChange()
        }
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
