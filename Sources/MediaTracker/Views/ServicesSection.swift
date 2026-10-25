import SwiftUI
import SwiftData
import UserNotifications

struct ServicesSection: View {
    // Credentials are held as view state and written through `Secrets`, which puts them in the
    // Keychain. `@AppStorage` cannot be used for them: it would write the plaintext back into the
    // defaults plist that the migration just cleaned out.
    @State private var tmdbApiKey = Secrets.value(for: .tmdb)
    @State private var omdbApiKey = Secrets.value(for: .omdb)
    @State private var mmApiKey = Secrets.value(for: .mooreMetrics)
    @AppStorage("notifications_enabled") private var notificationsEnabled = true
    @AppStorage("notifications_movies") private var movieNotificationsEnabled = true
    @AppStorage("notifications_tv") private var tvNotificationsEnabled = true
    @AppStorage("notifications_time") private var notificationTime: Double = 9 * 3600
    @AppStorage(UserDefaultsKeys.weeklyDigestEnabled.rawValue) private var weeklyDigestEnabled = false
    @AppStorage(UserDefaultsKeys.weeklyDigestWeekday.rawValue) private var weeklyDigestWeekday = 1
    @AppStorage(UserDefaultsKeys.weeklyDigestTime.rawValue) private var weeklyDigestTime: Double = 19 * 3600

    @AppStorage(UserDefaultsKeys.recommendationSource.rawValue) private var recommendationSource = "tmdb"
    @AppStorage(UserDefaultsKeys.syncTMDBFavorites.rawValue) private var syncTMDBFavorites = false
    @State private var isSyncingFavorites = false

    @AppStorage(UserDefaultsKeys.cloudSyncEnabled.rawValue) private var cloudSyncEnabled = false
    @AppStorage(UserDefaultsKeys.cloudSyncURL.rawValue) private var cloudSyncURL = ""
    @State private var cloudSyncAnonKey = Secrets.value(for: .cloudSyncAnonKey)
    @State private var cloudSyncKey = Secrets.value(for: .cloudSyncKey)
    @AppStorage(UserDefaultsKeys.cloudSyncLastTimestamp.rawValue) private var cloudSyncLastTimestamp: Double = 0
    @State private var isSyncingCloud = false
    @State private var hasCopiedSyncKey = false
    @State private var showCloudAnonKey = false
    @State private var isCheckingImpact = false
    @State private var showImpactDialog = false
    @State private var pendingImpact: CloudSyncService.SyncImpact? = nil

    private var currentSyncKey: String {
        if cloudSyncKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CloudSyncService.getOrGenerateSyncKey()
        }
        return cloudSyncKey
    }

    // Each field writes through to the Keychain as it is edited. A `Binding` rather than
    // `.onChange` so there is exactly one write path and the value can never be visible in the
    // field but missing from the store.
    private var tmdbKeyBinding: Binding<String> {
        Binding(get: { tmdbApiKey }, set: { tmdbApiKey = $0; Secrets.set($0, for: .tmdb) })
    }

    private var omdbKeyBinding: Binding<String> {
        Binding(get: { omdbApiKey }, set: { omdbApiKey = $0; Secrets.set($0, for: .omdb) })
    }

    private var mmKeyBinding: Binding<String> {
        Binding(get: { mmApiKey }, set: { mmApiKey = $0; Secrets.set($0, for: .mooreMetrics) })
    }

    private var cloudAnonKeyBinding: Binding<String> {
        Binding(
            get: { cloudSyncAnonKey },
            set: { cloudSyncAnonKey = $0; Secrets.set($0, for: .cloudSyncAnonKey) }
        )
    }

    private var lastSyncLabel: String {
        guard cloudSyncLastTimestamp > 0 else { return "Never synced" }
        let date = Date(timeIntervalSince1970: cloudSyncLastTimestamp)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Last synced " + formatter.localizedString(for: date, relativeTo: Date())
    }

    @State private var showTMDBKey = false
    @State private var showOMDBKey = false
    @State private var showMMKey = false
    @State private var tmdbValidation: KeyValidationState = .idle
    @State private var omdbValidation: KeyValidationState = .idle
    @Environment(\.colorScheme) var scheme
    @Environment(\.modelContext) private var modelContext

    enum KeyValidationState: Equatable {
        case idle
        case testing
        case valid
        case invalid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            SettingsCard(color: .green) {
                VStack(spacing: 0) {
                    apiKeyRow("TMDB", subtitle: "Movie & TV metadata", binding: tmdbKeyBinding, showKey: $showTMDBKey, link: "https://www.themoviedb.org/settings/api", validation: $tmdbValidation) {
                        await APIClient.shared.validateTMDBKey(key: tmdbApiKey)
                    }
                    apiKeyRow("OMDb", subtitle: "Rotten Tomatoes scores", binding: omdbKeyBinding, showKey: $showOMDBKey, link: "https://www.omdbapi.com/apikey.aspx", validation: $omdbValidation) {
                        await APIClient.shared.validateOMDBKey(key: omdbApiKey)
                    }
                    apiKeyRow("MooreMetrics", subtitle: "Show recommendations", binding: mmKeyBinding, showKey: $showMMKey, link: "https://www.mooremetrics.com", validation: nil)
                }
            }

            SettingsCard(color: .purple) {
                VStack(spacing: 0) {
                    SettingsLabeledRow(
                        title: "Recommendation Engine",
                        subtitle: recommendationSource == "tmdb"
                            ? "TMDB recommendations load automatically"
                            : "MooreMetrics custom preference & trait matching",
                        showDivider: true
                    ) {
                        Picker("", selection: $recommendationSource) {
                            Text("TMDB (Automatic)").tag("tmdb")
                            Text("MooreMetrics").tag("mooremetrics")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 260)
                    }

                    SettingsToggleRow(
                        title: "Sync Favorites with TMDB",
                        subtitle: "Two-way sync between your Loved titles and TMDB account favorites",
                        showDivider: syncTMDBFavorites,
                        isOn: $syncTMDBFavorites
                    )

                    if syncTMDBFavorites {
                        SettingsRow(
                            title: "Sync Now",
                            subtitle: "Push Loved items and pull remote TMDB favorites",
                            showDivider: false
                        ) {
                            SettingsButton(title: isSyncingFavorites ? "Syncing..." : "Sync Favorites") {
                                guard !isSyncingFavorites else { return }
                                isSyncingFavorites = true
                                Task {
                                    let service = BackgroundDataService(modelContainer: modelContext.container)
                                    let (pushed, pulled) = await service.syncFavoritesWithTMDB()
                                    await MainActor.run {
                                        isSyncingFavorites = false
                                        AppErrorState.shared.showToast(
                                            "Favorites synced (\(pushed) pushed, \(pulled) pulled)",
                                            style: .success
                                        )
                                    }
                                }
                            }
                            .disabled(isSyncingFavorites || tmdbApiKey.isEmpty)
                        }
                    }
                }
            }

            SettingsCard(color: .blue) {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        title: "Cross-Device Cloud Sync",
                        subtitle: "Sync watch states & episode progress across macOS and Android",
                        showDivider: cloudSyncEnabled,
                        isOn: $cloudSyncEnabled
                    )

                    if cloudSyncEnabled {
                        SettingsRow(
                            title: "Supabase Project URL",
                            subtitle: "Your personal Supabase project endpoint (e.g. https://xyz.supabase.co)",
                            showDivider: true
                        ) {
                            TextField("https://xyz.supabase.co", text: $cloudSyncURL)
                                .textFieldStyle(.plain)
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .frame(width: 260)
                        }

                        SettingsRow(
                            title: "Supabase Anon Key",
                            subtitle: "Publishable/Anon key from your Supabase dashboard",
                            showDivider: true
                        ) {
                            HStack(spacing: AppTheme.Spacing.small) {
                                Group {
                                    if showCloudAnonKey {
                                        TextField("sb_publishable_...", text: cloudAnonKeyBinding)
                                            .textFieldStyle(.plain)
                                    } else {
                                        SecureField("sb_publishable_...", text: cloudAnonKeyBinding)
                                            .textFieldStyle(.plain)
                                    }
                                }
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .frame(width: 220)

                                Button {
                                    showCloudAnonKey.toggle()
                                } label: {
                                    Image(systemName: showCloudAnonKey ? "eye.slash" : "eye")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(showCloudAnonKey ? "Hide API key" : "Show API key")
                                .contentShape(Rectangle())
                            }
                        }

                        SettingsRow(
                            title: "Secret Sync Key",
                            subtitle: "Enter this key in your Android companion app to pair devices",
                            showDivider: true
                        ) {
                            HStack(spacing: AppTheme.Spacing.small) {
                                Text(currentSyncKey)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 160, alignment: .trailing)

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(currentSyncKey, forType: .string)
                                    hasCopiedSyncKey = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        hasCopiedSyncKey = false
                                    }
                                } label: {
                                    Image(systemName: hasCopiedSyncKey ? "checkmark" : "doc.on.doc")
                                        .font(.caption)
                                        .foregroundStyle(hasCopiedSyncKey ? .green : .secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Copy Sync Key to Clipboard")
                                .accessibilityLabel("Copy sync key to the clipboard")
                                .contentShape(Rectangle())
                            }
                        }

                        SettingsRow(
                            title: "Sync With Cloud",
                            subtitle: lastSyncLabel,
                            showDivider: false
                        ) {
                            SettingsButton(title: isSyncingCloud ? "Syncing..." : (isCheckingImpact ? "Analyzing..." : "Sync Now")) {
                                guard !isSyncingCloud && !isCheckingImpact else { return }
                                isCheckingImpact = true
                                Task {
                                    let service = CloudSyncService(modelContainer: modelContext.container)
                                    let impact = await service.calculateSyncImpact()
                                    await MainActor.run {
                                        isCheckingImpact = false
                                        if let err = impact.errorDescription {
                                            AppErrorState.shared.showToast("Could not check cloud: \(err)", style: .warning)
                                        } else if !impact.hasChanges {
                                            AppErrorState.shared.showToast("No title conflicts or uploads", style: .success)
                                        } else {
                                            pendingImpact = impact
                                            showImpactDialog = true
                                        }
                                    }
                                }
                            }
                            .disabled(isSyncingCloud || isCheckingImpact)
                        }
                    }
                }
            }
            .sheet(isPresented: $showImpactDialog) {
                if let impact = pendingImpact {
                    SyncImpactSheet(
                        impact: impact,
                        onConfirmSelectiveSync: { importIDs, updateIDs, uploadIDs, syncEps in
                            showImpactDialog = false
                            isSyncingCloud = true
                            Task {
                                let service = CloudSyncService(modelContainer: modelContext.container)
                                let res = await service.performSelectiveSync(
                                    approvedImportIDs: importIDs,
                                    approvedUpdateIDs: updateIDs,
                                    approvedUploadIDs: uploadIDs,
                                    syncEpisodes: syncEps
                                )
                                await MainActor.run {
                                    isSyncingCloud = false
                                    if let err = res.errorDescription {
                                        AppErrorState.shared.showToast("Cloud sync failed: \(err)", style: .warning)
                                    } else {
                                        let total = res.mediaPushed + res.mediaPulled + res.episodesPushed + res.episodesPulled
                                        AppErrorState.shared.showToast(
                                            "Sync complete (\(total) changes)",
                                            style: .success
                                        )
                                    }
                                }
                            }
                        },
                        onConfirmBackup: {
                            showImpactDialog = false
                            isSyncingCloud = true
                            Task {
                                let service = CloudSyncService(modelContainer: modelContext.container)
                                let res = await service.backupToCloud()
                                await MainActor.run {
                                    isSyncingCloud = false
                                    if let err = res.errorDescription {
                                        AppErrorState.shared.showToast("Backup failed: \(err)", style: .warning)
                                    } else {
                                        AppErrorState.shared.showToast(
                                            "Mac successfully backed up to Cloud (\(res.mediaPushed) titles, \(res.episodesPushed) episodes)",
                                            style: .success
                                        )
                                    }
                                }
                            }
                        },
                        onDismiss: {
                            showImpactDialog = false
                        }
                    )
                }
            }

            SettingsCard(color: .red) {
                VStack(spacing: 0) {
                    SettingsToggleRow(title: "Enable Notifications", subtitle: "Get notified about new episodes and movies", showDivider: notificationsEnabled, isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, enabled in
                            if enabled {
                                Task {
                                    await NotificationManager.shared.requestPermission()
                                    await NotificationManager.shared.scheduleAllUpcomingNotifications()
                                }
                            } else {
                                Task { NotificationManager.shared.removeAllPendingNotifications() }
                            }
                        }

                    if notificationsEnabled {
                        SettingsLabeledRow(title: "Channels", subtitle: nil, showDivider: true) {
                            HStack(spacing: AppTheme.Spacing.tiny) {
                                channelChip("Movies", isOn: $movieNotificationsEnabled)
                                channelChip("TV Shows", isOn: $tvNotificationsEnabled)
                            }
                        }

                        SettingsLabeledRow(title: "Delivery Time", subtitle: nil, showDivider: true) {
                            DatePicker("", selection: Binding(
                                get: { Date(timeIntervalSince1970: notificationTime) },
                                set: { notificationTime = $0.timeIntervalSince1970.truncatingRemainder(dividingBy: TimeInterval.secondsInDay) }
                            ), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .controlSize(.small)
                        }

                        SettingsToggleRow(title: "Weekly Digest", subtitle: "Your shows & movies, every week", showDivider: weeklyDigestEnabled, isOn: $weeklyDigestEnabled)
                            .onChange(of: weeklyDigestEnabled) { _, _ in
                                Task { await NotificationManager.shared.rescheduleWeeklyDigestIfNeeded() }
                            }

                        if weeklyDigestEnabled {
                            SettingsLabeledRow(title: "Digest Day", subtitle: nil, showDivider: true) {
                                Picker("", selection: $weeklyDigestWeekday) {
                                    ForEach(1...7, id: \.self) { weekday in
                                        Text(Self.weekdayName(weekday)).tag(weekday)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(width: 120)
                            }
                            .onChange(of: weeklyDigestWeekday) { _, _ in
                                Task { await NotificationManager.shared.rescheduleWeeklyDigestIfNeeded() }
                            }

                            SettingsLabeledRow(title: "Digest Time", subtitle: nil, showDivider: true) {
                                DatePicker("", selection: Binding(
                                    get: { Date(timeIntervalSince1970: weeklyDigestTime) },
                                    set: { weeklyDigestTime = $0.timeIntervalSince1970.truncatingRemainder(dividingBy: TimeInterval.secondsInDay) }
                                ), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .controlSize(.small)
                            }
                            .onChange(of: weeklyDigestTime) { _, _ in
                                Task { await NotificationManager.shared.rescheduleWeeklyDigestIfNeeded() }
                            }
                        }

                        SettingsRow(title: "Reschedule", subtitle: "Refresh notification queue", showDivider: false) {
                            SettingsButton(title: "Reschedule All") {
                                Task { await NotificationManager.shared.scheduleAllUpcomingNotifications() }
                            }
                        }
                    }
                }
            }
        }
        // Opening this tab is where the credentials are first read, so it is also the right place
        // to re-home them if the app has been re-signed since they were written. The reads above
        // have already asked for approval if the ACL was stale; this rewrites the items so that
        // approval becomes permanent instead of recurring on the next launch.
        .task { Secrets.adoptIfSigningIdentityChanged() }
    }

    private func apiKeyRow(_ name: String, subtitle: String, binding: Binding<String>, showKey: Binding<Bool>, link: String, validation: Binding<KeyValidationState>?, testAction: (() async -> Bool)? = nil) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.small) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                    HStack(spacing: AppTheme.Spacing.mini) {
                        Text(name)
                            .font(AppTheme.Font.settingsRowTitle)
                            .foregroundStyle(.primary)
                        StatusBadge(text: binding.wrappedValue.isEmpty ? "Missing" : "Connected", isActive: !binding.wrappedValue.isEmpty)
                    }
                    Text(subtitle)
                        .font(AppTheme.Font.settingsSubtitle)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: AppTheme.Spacing.tiny) {
                    ZStack(alignment: .trailing) {
                        if showKey.wrappedValue {
                            TextField("Enter API key...", text: binding)
                        } else {
                            SecureField("Enter API key...", text: binding)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(AppTheme.Font.label)
                    .padding(.vertical, AppTheme.Spacing.mini)
                    .padding(.horizontal, AppTheme.Spacing.tiny)
                    .frame(width: 180)
                    .background(AppTheme.Colors.surfaceGhost(for: scheme))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                            .stroke(AppTheme.Colors.strokeDefault(for: scheme), lineWidth: 0.5)
                    )

                    Button {
                        showKey.wrappedValue.toggle()
                    } label: {
                        Image(systemName: showKey.wrappedValue ? "eye.slash" : "eye")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .accessibilityLabel(showKey.wrappedValue ? "Hide API key" : "Show API key")

                    if let validation, let testAction {
                        let state = validation.wrappedValue
                        if state != .idle {
                            Image(systemName: state == .valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(AppTheme.Font.caption)
                                .foregroundStyle(state == .valid ? .green : .red)
                                .help(state == .valid ? "Key is valid" : "Key could not be validated")
                        }

                        Button {
                            guard !binding.wrappedValue.isEmpty else { return }
                            validation.wrappedValue = .testing
                            Task {
                                let isValid = await testAction()
                                await MainActor.run {
                                    validation.wrappedValue = isValid ? .valid : .invalid
                                }
                            }
                        } label: {
                            if validation.wrappedValue == .testing {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "checkmark.seal")
                                    .font(AppTheme.Font.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                        .disabled(binding.wrappedValue.isEmpty || validation.wrappedValue == .testing)
                        .accessibilityLabel("Test \(name) API key")
                    }

                    if let linkURL = URL(string: link) {
                        Link(destination: linkURL) {
                            Image(systemName: "arrow.up.right.square")
                                .font(AppTheme.Font.label)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                        .help("Get a \(name) API key")
                    } else {
                        let _ = AppLogger.debug("Malformed API key link for \(name): \(link)")
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)
        }
    }

    private static func weekdayName(_ weekday: Int) -> String {
        let names = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return weekday >= 1 && weekday <= 7 ? names[weekday] : "Sunday"
    }

    private func channelChip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(AppTheme.Animation.springSnappy) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.micro) {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(AppTheme.Font.label)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(AppTheme.Font.label)
                    .foregroundStyle(isOn.wrappedValue ? .primary : .secondary)
            }
            .padding(.horizontal, AppTheme.Spacing.tiny)
            .padding(.vertical, AppTheme.Spacing.micro)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(isOn.wrappedValue ? .secondary.opacity(0.06) : Color.primary.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}
