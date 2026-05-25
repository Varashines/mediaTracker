import ServiceManagement
import SwiftData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("tmdb_api_key") private var tmdbApiKey = ""
    @AppStorage("omdb_api_key") private var omdbApiKey = ""
    @AppStorage("studio_aliases") private var studioAliases = ""
    @AppStorage("theme_preference") private var themePreference: Int = 0

    // Feedback Switches
    @AppStorage("haptics_enabled") private var hapticsEnabled = true
    @AppStorage("audio_enabled") private var audioEnabled = true
    @AppStorage("prevent_sleep_mode") private var preventSleepMode = false
    @AppStorage("auto_mark_episodes_watched") private var autoMarkEpisodesWatched = true

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var selectedTab = 0
    @State private var showClearDatabaseConfirmation = false
    @State private var showNotificationDebug = false
    @State private var isPulsing = false
    @Namespace private var headerNamespace

    // Notification Preferences
    @AppStorage("notifications_enabled") private var notificationsEnabled = true
    @AppStorage("notifications_movies") private var movieNotificationsEnabled = true
    @AppStorage("notifications_tv") private var tvNotificationsEnabled = true
    @AppStorage("notifications_time") private var notificationTime: Double = 9 * 3600

    var body: some View {
        VStack(spacing: 0) {
            // High-End Modern Tab Bar
            HStack {
                Spacer()
                HStack(spacing: 2) {
                    modernTabButton(title: "General", icon: "gearshape", index: 0)
                    modernTabButton(title: "Connect", icon: "network", index: 1)
                    modernTabButton(title: "Engine", icon: "cpu", index: 2)
                    modernTabButton(title: "Vault", icon: "tray.full", index: 3)
                }
                .padding(4)
                .background(.ultraThinMaterial.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer()
            }
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider().opacity(0.12)

            // Content Area
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    Group {
                        switch selectedTab {
                        case 0: generalTab
                        case 1: connectivityTab
                        case 2: engineTab
                        case 3: vaultTab
                        default: EmptyView()
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))
                }
                .padding(.horizontal, AppTheme.Spacing.large)
                .padding(.vertical, AppTheme.Spacing.large)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 480, maxWidth: 650, minHeight: 520)
        .fontDesign(.rounded)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: selectedTab)
        .onAppear {
            Task {
                guard !studioAliases.isEmpty else { return }
                StudioAliasManagerView.migrateLegacyAliases(from: studioAliases, into: modelContext.container)
                await MainActor.run { studioAliases = "" }
            }
        }
    }

    private static let tabFillIcons: [String: String] = [
        "gearshape": "gearshape.fill",
        "tray.full": "tray.full.fill",
        "cpu": "cpu.fill",
        "network": "network",
    ]

    private func modernTabButton(title: String, icon: String, index: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                selectedTab = index
            }
            FeedbackManager.shared.trigger(.click)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selectedTab == index
                    ? (Self.tabFillIcons[icon] ?? "\(icon).fill")
                    : icon
                )
                .font(.system(size: 11, weight: .bold))

                Text(title)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background {
                if selectedTab == index {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: gradientForTab(index),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .matchedGeometryEffect(id: "settings_active_tab", in: headerNamespace)
                        .shadow(
                            color: gradientForTab(index).first!.opacity(0.24),
                            radius: 4,
                            x: 0,
                            y: 1.5
                        )
                }
            }
            .foregroundStyle(selectedTab == index ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func gradientForTab(_ index: Int) -> [Color] {
        switch index {
        case 0: return [Color.blue, Color.indigo]
        case 1: return [Color.pink, Color.red]
        case 2: return [Color.blue, Color.teal]
        case 3: return [Color.orange, Color.red]
        default: return [Color.blue, Color.indigo]
        }
    }

    // MARK: - Tabs

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            settingsHeader("Appearance", icon: "paintbrush", gradientColors: [Color.purple, Color.indigo])

            GroupContainer {
                modernRow(title: "Theme Mode", subtitle: "Select the application visual style.", showDivider: false) {
                    CustomThemePicker(selection: $themePreference)
                }
            }

            settingsHeader("Tracking Behavior", icon: "play.square.stack", gradientColors: [Color.blue, Color.teal])

            GroupContainer {
                modernToggle(
                    "Auto-Complete TV Shows",
                    subtitle: "Marking completed completes all episodes.",
                    isOn: $autoMarkEpisodesWatched
                )
            }

            settingsHeader("Feedback & Power", icon: "bolt.fill", gradientColors: [Color.orange, Color.red])

            GroupContainer {
                modernToggle(
                    "Tactile Haptics",
                    subtitle: "Vibrate on interactions.",
                    showDivider: true,
                    isOn: $hapticsEnabled
                )

                modernToggle(
                    "Audio Feedback",
                    subtitle: "Play sounds on actions.",
                    showDivider: true,
                    isOn: $audioEnabled
                )

                modernToggle(
                    "Launch at Login",
                    subtitle: "Open automatically at login.",
                    showDivider: true,
                    isOn: $launchAtLogin
                )
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            if SMAppService.mainApp.status != .enabled {
                                try SMAppService.mainApp.register()
                            }
                        } else {
                            if SMAppService.mainApp.status == .enabled {
                                try SMAppService.mainApp.unregister()
                            }
                        }
                    } catch {
                        AppLogger.error("Failed to update launch at login: \(error)")
                    }
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }

                modernToggle(
                    "Prevent Sleep",
                    subtitle: "Keep Mac awake for background sync.",
                    showDivider: false,
                    isOn: $preventSleepMode
                )
            }
        }
    }

    private var connectivityTab: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            settingsHeader("Connectivity", icon: "network", gradientColors: [Color.blue, Color.teal])

            GroupContainer {
                modernRow(
                    title: "TMDB API Key",
                    subtitle: "Enable movie & TV metadata syncing.",
                    showDivider: false
                ) {
                    HStack(spacing: 8) {
                        // Pulsing Status Dot
                        HStack(spacing: 5) {
                            Circle()
                                .fill(tmdbApiKey.isEmpty ? Color.red : Color.green)
                                .frame(width: 7, height: 7)
                                .opacity(isPulsing ? 0.35 : 1.0)
                                .animation(
                                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                                    value: isPulsing
                                )
                            Text(tmdbApiKey.isEmpty ? "Missing Key" : "Connected")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(tmdbApiKey.isEmpty ? .red.opacity(0.8) : .green.opacity(0.8))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill((tmdbApiKey.isEmpty ? Color.red : Color.green).opacity(0.08))
                        )
                        .overlay(
                            Capsule()
                                .stroke((tmdbApiKey.isEmpty ? Color.red : Color.green).opacity(0.15), lineWidth: 0.5)
                        )

                        SecureField("API Key...", text: $tmdbApiKey)
                            .textFieldStyle(.plain)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(Color.primary.opacity(0.035))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                            )
                            .font(.system(size: 10.5, design: .monospaced))
                            .frame(width: 140)

                        Link(destination: URL(string: "https://www.themoviedb.org/settings/api")!) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.08))
                                    .frame(width: 22, height: 22)
                                Image(systemName: "key.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Get TMDB API Key")
                    }
                }
            }
            .onAppear {
                isPulsing = true
            }

            GroupContainer {
                modernRow(
                    title: "OMDb API Key",
                    subtitle: "Rotten Tomatoes critic scores for movies.",
                    showDivider: false
                ) {
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(omdbApiKey.isEmpty ? Color.red : Color.green)
                                .frame(width: 7, height: 7)
                            Text(omdbApiKey.isEmpty ? "Optional" : "Connected")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(omdbApiKey.isEmpty ? Color.secondary : Color.green.opacity(0.8))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill((omdbApiKey.isEmpty ? Color.secondary : Color.green).opacity(0.08))
                        )
                        .overlay(
                            Capsule()
                                .stroke((omdbApiKey.isEmpty ? Color.secondary : Color.green).opacity(0.15), lineWidth: 0.5)
                        )

                        SecureField("API Key...", text: $omdbApiKey)
                            .textFieldStyle(.plain)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(Color.primary.opacity(0.035))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                            )
                            .font(.system(size: 10.5, design: .monospaced))
                            .frame(width: 140)

                        Link(destination: URL(string: "https://www.omdbapi.com/apikey.aspx")!) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.08))
                                    .frame(width: 22, height: 22)
                                Image(systemName: "key.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Get OMDb API Key")
                    }
                }
            }

            settingsHeader("Notifications", icon: "bell.fill", gradientColors: [Color.pink, Color.red])

            GroupContainer {
                modernToggle(
                    "Enable Notifications",
                    subtitle: "Receive desktop release alerts.",
                    showDivider: notificationsEnabled,
                    isOn: $notificationsEnabled
                )
                .onChange(of: notificationsEnabled) { _, enabled in
                    if enabled {
                        NotificationManager.shared.requestPermission()
                        Task { await NotificationManager.shared.scheduleAllUpcomingNotifications() }
                    } else {
                        Task {
                            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                        }
                    }
                }

                if notificationsEnabled {
                    // Content Channels Selection
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Notification Channels")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)

                        HStack(spacing: AppTheme.Spacing.medium) {
                            CustomNotificationCheckbox(
                                title: "Movies",
                                icon: "film",
                                isOn: $movieNotificationsEnabled
                            )
                            
                            CustomNotificationCheckbox(
                                title: "TV Shows",
                                icon: "tv",
                                isOn: $tvNotificationsEnabled
                            )
                        }
                        .padding(.bottom, 6)
                    }
                    .padding(.horizontal, AppTheme.Spacing.small)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    
                    Divider()
                        .opacity(0.12)
                        .padding(.horizontal, 8)

                    // Delivery Hour
                    modernRow(
                        title: "Preferred Delivery Time",
                        subtitle: "Daily notification delivery time.",
                        showDivider: false
                    ) {
                        DatePicker("", selection: Binding(
                            get: { Date(timeIntervalSince1970: notificationTime) },
                            set: { notificationTime = $0.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400) }
                        ), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .controlSize(.regular)
                    }
                    .transition(.opacity)
                }

                Divider()
                    .opacity(0.12)
                    .padding(.horizontal, 8)

                modernRow(
                    title: "Scheduled Queue",
                    subtitle: "Reset notifications or inspect queue.",
                    showDivider: false
                ) {
                    HStack(spacing: 12) {
                        Button {
                            Task { await NotificationManager.shared.scheduleAllUpcomingNotifications() }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                Text("Reschedule All")
                            }
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!notificationsEnabled)

                        Button {
                            showNotificationDebug = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("Review Schedule")
                                Image(systemName: "chevron.right")
                            }
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(isPresented: $showNotificationDebug) { NotificationDebugView() }
    }

    private var engineTab: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            settingsHeader("Data Processing", icon: "brain", gradientColors: [Color.green, Color.emerald])

            VStack(alignment: .leading, spacing: 12) {
                Text("STUDIO ALIASES")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)

                GroupContainer {
                    StudioAliasManagerView().padding(.vertical, 4)
                }

                Text("CONTENT FILTERS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.horizontal, 4)

                GroupContainer {
                    DiscoveryManagementView().padding(.vertical, 4)
                }
            }
        }
    }

    private var vaultTab: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            settingsHeader("Maintenance", icon: "wrench.and.screwdriver.fill", gradientColors: [Color.orange, Color.red])

            GroupContainer {
                modernRow(
                    title: "Manual Backup",
                    subtitle: "Export or import your collection backup.",
                    showDivider: true
                ) {
                    HStack(spacing: 8) {
                        capsuleButton("Export") {
                            let container = modelContext.container
                            Task {
                                let context = ModelContext(container)
                                let descriptor = FetchDescriptor<MediaItem>(sortBy: [SortDescriptor(\.title)])
                                if let items = try? context.fetch(descriptor) {
                                    await MainActor.run {
                                        LibraryImportExportService.shared.exportLibrary(items: items)
                                    }
                                }
                            }
                        }
                        capsuleButton("Import") {
                            LibraryImportExportService.shared.importLibrary(modelContext: modelContext)
                        }
                    }
                }

                modernRow(
                    title: "Auto Backup Location",
                    subtitle: "Show automatic backups in Finder.",
                    showDivider: true
                ) {
                    capsuleButton("Show in Finder") {
                        let url = URL.applicationSupportDirectory.appendingPathComponent("AutoBackups")
                        if !FileManager.default.fileExists(atPath: url.path) {
                            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        }
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                    }
                }

                modernRow(
                    title: "Database Repair",
                    subtitle: "Fix relationships and legacy duplicates.",
                    showDivider: true
                ) {
                    capsuleButton("Start Repair") {
                        DataService.shared.runMaintenance(modelContext: modelContext)
                    }
                }

                modernRow(
                    title: "Image Cache",
                    subtitle: "Delete cached poster images.",
                    showDivider: false
                ) {
                    capsuleButton("Purge Cache", color: .red) {
                        ImageCache.shared.clearFullCache()
                    }
                }
            }

            settingsHeader("Danger Zone", icon: "exclamationmark.triangle.fill", gradientColors: [Color.red, Color.orange])

            GroupContainer(isDangerZone: true) {
                Button {
                    showClearDatabaseConfirmation = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Delete All Library Data")
                                .font(AppTheme.Font.bodyBold)
                                .foregroundStyle(.red)
                            Text("Wipe entire library. This cannot be undone.")
                                .font(AppTheme.Font.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text("MediaTracker v\(appVersion)")
                .font(AppTheme.Font.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, AppTheme.Spacing.tiny)
        }
        .confirmationDialog("Reset App?", isPresented: $showClearDatabaseConfirmation) {
            Button("Delete Everything", role: .destructive) {
                DataService.shared.clearDatabase(modelContext: modelContext)
            }
        }
    }

    // MARK: - Helpers

    private func settingsHeader(_ title: String, icon: String, gradientColors: [Color]) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                    .shadow(
                        color: (gradientColors.first ?? .clear).opacity(0.3),
                        radius: 5,
                        x: 0,
                        y: 2.5
                    )

                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, AppTheme.Spacing.micro)
    }

    private func modernRow<Content: View>(
        title: String,
        subtitle: String,
        showDivider: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppTheme.Font.body)
                        .foregroundStyle(.primary)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(AppTheme.Font.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: AppTheme.Spacing.medium)
                content()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())

            if showDivider {
                Divider()
                    .opacity(0.12)
                    .padding(.horizontal, 8)
            }
        }
    }

    private func modernToggle(_ title: String, subtitle: String, showDivider: Bool = false, isOn: Binding<Bool>) -> some View {
        modernRow(title: title, subtitle: subtitle, showDivider: showDivider) {
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .onTapGesture {
            withAnimation(AppTheme.Animation.springDefault) {
                isOn.wrappedValue.toggle()
            }
            FeedbackManager.shared.trigger(.click)
        }
    }

    private func capsuleButton(_ title: String, color: Color = .accentColor, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(color.opacity(0.2), lineWidth: 0.5)
            )
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "6.0.0"
    }
}



