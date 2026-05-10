import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \MediaItem.title) private var allItems: [MediaItem]
    @AppStorage("tmdb_api_key") private var tmdbApiKey = ""
    @AppStorage("studio_aliases") private var studioAliases = ""
    @AppStorage("theme_style") private var themeStyle: ThemeStyle = .standard
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    @AppStorage("theme_preference") private var themePreference: Int = 0 
    
    // Feedback Switches
    @AppStorage("haptics_enabled") private var hapticsEnabled = true
    @AppStorage("audio_enabled") private var audioEnabled = true
    @AppStorage("prevent_sleep_mode") private var preventSleepMode = false
    @AppStorage("auto_mark_episodes_watched") private var autoMarkEpisodesWatched = true
    
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
                    modernTabButton(title: "Design", icon: "paintpalette", index: 1)
                    modernTabButton(title: "Engine", icon: "cpu", index: 2)
                    modernTabButton(title: "Vault", icon: "tray.full", index: 3)
                }
                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial)
            
            Divider().opacity(0.4)
            
            // Content Area
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Group {
                        switch selectedTab {
                        case 0: generalTab
                        case 1: appearanceTab
                        case 2: discoveryTab
                        case 3: maintenanceTab
                        default: EmptyView()
                        }
                    }
                }
                .padding(32)
            }
            .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
        }
        .frame(width: 600, height: 680)
        .fontDesign(.rounded)
        .animation(.spring(duration: 0.3, bounce: 0.1), value: selectedTab)
    }

    private func modernTabButton(title: String, icon: String, index: Int) -> some View {
        Button {
            selectedTab = index
            FeedbackManager.shared.trigger(.click)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: selectedTab == index ? "\(icon).fill" : icon)
                    .font(.system(size: 20))
                    .foregroundStyle(selectedTab == index ? adaptiveAccent : .primary.opacity(0.4))
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
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tabs

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 32) {
            settingsHeader("Connectivity")
            
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
                        .foregroundStyle(adaptiveAccent)
                    }
                }
            }

            settingsHeader("Feedback & Power")
            
            GroupContainer {
                modernToggle("Tactile Haptics", subtitle: "Physical feedback on actions.", isOn: $hapticsEnabled)
                Divider().opacity(0.3)
                modernToggle("Audio Feedback", subtitle: "Sound effects on selection.", isOn: $audioEnabled)
                Divider().opacity(0.3)
                modernToggle("Launch at Login", subtitle: "Start app automatically.", isOn: .constant(false)) // Placeholder
                Divider().opacity(0.3)
                modernToggle("Prevent Sleep", subtitle: "Keep background sync active.", isOn: $preventSleepMode)
            }
            
            settingsHeader("Notifications")
            
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
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showNotificationDebug) { NotificationDebugView() }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 32) {
            settingsHeader("Accent Color")
            
            GroupContainer {
                HStack(spacing: 12) {
                    ForEach(AppAccent.allCases) { accent in
                        Circle()
                            .fill(accent.color(for: colorScheme).gradient)
                            .frame(width: 26, height: 26)
                            .overlay {
                                if appAccent == accent {
                                    Circle()
                                        .stroke(Color.primary, lineWidth: 2)
                                        .frame(width: 36, height: 36)
                                }
                            }
                            .onTapGesture { 
                                withAnimation(.snappy) { appAccent = accent }
                                FeedbackManager.shared.trigger(.click)
                            }
                    }
                }
                .frame(height: 36)
                .frame(maxWidth: .infinity)
            }

            settingsHeader("User Interface")
            
            GroupContainer {
                modernToggle("Glassmorphism", subtitle: "Enable translucent frosted materials.", isOn: Binding(get: { themeStyle == .brand }, set: { themeStyle = $0 ? .brand : .standard }))
                Divider().opacity(0.3)
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
        }
    }

    // Re-using same logic but keeping it clean for the new style
    private var discoveryTab: some View {
        VStack(alignment: .leading, spacing: 32) {
            settingsHeader("Data Processing")
            
            VStack(alignment: .leading, spacing: 12) {
                Text("STUDIO ALIASES").font(.system(size: 10, weight: .black)).foregroundStyle(.tertiary)
                GroupContainer {
                    StudioAliasManagerView().padding(.vertical, 8)
                }
                
                Text("CONTENT FILTERS").font(.system(size: 10, weight: .black)).foregroundStyle(.tertiary).padding(.top, 8)
                GroupContainer {
                    DiscoveryManagementView().padding(.vertical, 8)
                }
            }
        }
    }

    private var maintenanceTab: some View {
        VStack(alignment: .leading, spacing: 32) {
            settingsHeader("Maintenance")
            
            GroupContainer {
                modernRow(title: "Library Backup", subtitle: "Export or import your entire library.") {
                    HStack(spacing: 8) {
                        Button("Export") { LibraryImportExportService.shared.exportLibrary(items: allItems) }.buttonStyle(.bordered)
                        Button("Import") { LibraryImportExportService.shared.importLibrary(modelContext: modelContext) }.buttonStyle(.bordered)
                    }
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

            settingsHeader("Danger Zone")
            
            GroupContainer {
                Button { showClearDatabaseConfirmation = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete All Data").font(.headline).foregroundStyle(.red)
                            Text("Permanently remove everything. Cannot be undone.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "trash.fill").foregroundStyle(.red)
                    }
                }
                .buttonStyle(.plain)
            }
            
            Text("MediaTracker v\(appVersion)").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
        }
        .confirmationDialog("Reset App?", isPresented: $showClearDatabaseConfirmation) {
            Button("Delete Everything", role: .destructive) { DataService.shared.clearDatabase(modelContext: modelContext) }
        }
    }

    private var appearanceTab: some View { appearanceSection }

    // MARK: - Helpers

    private func settingsHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.primary)
    }

    private func modernRow<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            content()
        }
        .padding(.vertical, 8)
    }

    private func modernToggle(_ title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        modernRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var adaptiveAccent: Color {
        appAccent.color(for: colorScheme)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "5.0.0"
    }
}

struct GroupContainer<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(20)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        }
    }
}
