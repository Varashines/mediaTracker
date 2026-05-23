import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("tmdb_api_key") private var tmdbApiKey = ""
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
    @Namespace private var headerNamespace

    var body: some View {
        VStack(spacing: 0) {
            // High-End Modern Header
            HStack(spacing: 0) {
                Spacer()
                HStack(spacing: 2) {
                    modernTabButton(title: "General", icon: "gearshape", index: 0)
                    modernTabButton(title: "Connect", icon: "network", index: 1)
                    modernTabButton(title: "Engine", icon: "cpu", index: 2)
                    modernTabButton(title: "Vault", icon: "tray.full", index: 3)
                }
                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 12)
            
            Divider().opacity(0.4)
            
            // Content Area
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Group {
                        switch selectedTab {
                        case 0: generalTab
                        case 1: connectivityTab
                        case 2: engineTab
                        case 3: vaultTab
                        default: EmptyView()
                        }
                    }
                }
                .padding(32)
            }
            .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
        }
        .frame(minWidth: 600, minHeight: 500)
        .fontDesign(.rounded)
        .animation(.spring(duration: 0.3, bounce: 0.1), value: selectedTab)
    }

    private func modernTabButton(title: String, icon: String, index: Int) -> some View {
        Button {
            selectedTab = index
            FeedbackManager.shared.trigger(.click)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: selectedTab == index ? (icon == "gearshape" ? "gearshape.fill" : (icon == "tray.full" ? "tray.full.fill" : (icon == "cpu" ? "cpu.fill" : (icon == "network" ? "network" : "\(icon).fill")))) : icon)
                    .font(.system(size: 20))
                    .foregroundStyle(selectedTab == index ? Color.accentColor : .primary.opacity(0.4))
                    .frame(width: 32, height: 32)
                
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selectedTab == index ? .primary : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                if selectedTab == index {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                        .matchedGeometryEffect(id: "tab_bg", in: headerNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tabs

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsHeader("Appearance", icon: "paintbrush", color: .purple)
            
            GroupContainer {
                modernRow(title: "Theme Mode", subtitle: "Switch between light and dark UI.") {
                    Picker("", selection: $themePreference) {
                        Text("Auto").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }

            settingsHeader("Tracking Behavior", icon: "play.square.stack", color: .blue)
            
            GroupContainer {
                modernToggle("Auto-Complete TV Shows", subtitle: "Marking a show completed automatically marks all episodes watched.", isOn: $autoMarkEpisodesWatched)
            }

            settingsHeader("Feedback & Power", icon: "bolt.fill", color: .orange)
            
            GroupContainer {
                modernToggle("Tactile Haptics", subtitle: "Physical feedback on actions.", isOn: $hapticsEnabled)
                Divider().opacity(0.3)
                modernToggle("Audio Feedback", subtitle: "Sound effects on selection.", isOn: $audioEnabled)
                Divider().opacity(0.3)
                modernToggle("Launch at Login", subtitle: "Start app automatically.", isOn: $launchAtLogin)
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
                            print("Failed to update launch at login: \(error)")
                        }
                        // Refresh state to match reality
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                Divider().opacity(0.3)
                modernToggle("Prevent Sleep", subtitle: "Keep background sync active.", isOn: $preventSleepMode)
            }
        }
    }

    private var connectivityTab: some View {
        VStack(alignment: .leading, spacing: 32) {
            settingsHeader("Connectivity", icon: "network", color: .blue)
            
            GroupContainer {
                modernRow(title: "TMDB API Key", subtitle: "Required for movie and series metadata sync.") {
                    HStack(spacing: 8) {
                        SecureField("Enter Key", text: $tmdbApiKey)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 200)
                        
                        Link(destination: URL(string: "https://www.themoviedb.org/settings/api")!) {
                            Image(systemName: "questionmark.circle.fill").font(.title3)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
            
            settingsHeader("Notifications", icon: "bell.fill", color: .red)
            
            GroupContainer {
                Button { showNotificationDebug = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Upcoming Schedule").font(.headline)
                            Text("Review and cross-examine system alerts.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showNotificationDebug) { NotificationDebugView() }
    }

    private var engineTab: some View {
        VStack(alignment: .leading, spacing: 32) {
            settingsHeader("Data Processing", icon: "brain", color: .green)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("STUDIO ALIASES").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                GroupContainer {
                    StudioAliasManagerView().padding(.vertical, 8)
                }
                
                Text("CONTENT FILTERS").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary).padding(.top, 8)
                GroupContainer {
                    DiscoveryManagementView().padding(.vertical, 8)
                }
            }
        }
    }

    private var vaultTab: some View {
        VStack(alignment: .leading, spacing: 32) {
            settingsHeader("Maintenance", icon: "wrench.and.screwdriver.fill", color: .blue)
            
            GroupContainer {
                modernRow(title: "Library Backup", subtitle: "Export or import your entire library.") {
                    HStack(spacing: 8) {
                        Button("Export") {
                            let descriptor = FetchDescriptor<MediaItem>(sortBy: [SortDescriptor(\.title)])
                            if let items = try? modelContext.fetch(descriptor) {
                                LibraryImportExportService.shared.exportLibrary(items: items)
                            }
                        }.buttonStyle(.bordered)
                        Button("Import") { LibraryImportExportService.shared.importLibrary(modelContext: modelContext) }.buttonStyle(.bordered)
                    }
                }
                Divider().opacity(0.3)
                modernRow(title: "Auto Backup Location", subtitle: "Where automated backups are saved.") {
                    Button("Show in Finder") {
                        let url = URL.applicationSupportDirectory.appendingPathComponent("AutoBackups")
                        if !FileManager.default.fileExists(atPath: url.path) {
                            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        }
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                    }
                    .buttonStyle(.bordered)
                }
                Divider().opacity(0.3)
                modernRow(title: "Database Repair", subtitle: "Scan and heal relationship integrity.") {
                    Button("Start Repair") { DataService.shared.runMaintenance(modelContext: modelContext) }
                        .buttonStyle(.bordered)
                }
                Divider().opacity(0.3)
                modernRow(title: "Image Cache", subtitle: "Free up disk space by purging posters.") {
                    Button("Purge Cache") { ImageCache.shared.clearFullCache() }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                }
            }

            settingsHeader("Danger Zone", icon: "exclamationmark.triangle.fill", color: .red)
            
            GroupContainer {
                Button { showClearDatabaseConfirmation = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete All Data")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.red)
                            Text("Permanently remove everything. Cannot be undone.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "trash.fill").foregroundStyle(.red)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            Text("MediaTracker v\(appVersion)").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
        }
        .confirmationDialog("Reset App?", isPresented: $showClearDatabaseConfirmation) {
            Button("Delete Everything", role: .destructive) { DataService.shared.clearDatabase(modelContext: modelContext) }
        }
    }

    // MARK: - Helpers

    private func settingsHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.primary)
            
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
        }
    }

    private func modernRow<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            content()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func modernToggle(_ title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        modernRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .onTapGesture {
            withAnimation {
                isOn.wrappedValue.toggle()
            }
            FeedbackManager.shared.trigger(.click)
        }
    }

    private var adaptiveAccent: Color {
        Color.accentColor
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "5.0.0"
    }
}

struct GroupContainer<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(14)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        }
    }
}

#Preview("Settings View") {
    SettingsView()
        .modelContainer(try! ModelContainer(
            for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self,
                 MediaCollection.self, StudioAliasEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ))
}
