import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
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
    
    @Environment(\.colorScheme) var colorScheme
    @State private var containerWidth: CGFloat = 0
    @State private var showClearDatabaseConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Settings")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                    Text("Configure your MediaTracker experience across device and library.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 40)
                .padding(.top, 40)
                
                // Dashboard Bento Layout (Masonry)
                Group {
                    if containerWidth > 850 {
                        HStack(alignment: .top, spacing: 32) {
                            VStack(spacing: 32) {
                                appearanceCard
                                connectivityCard
                                dataMaintenanceCard
                            }
                            .frame(maxWidth: .infinity)
                            
                            VStack(spacing: 32) {
                                generalCard
                                discoveryCard
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 32) {
                            appearanceCard
                            generalCard
                            connectivityCard
                            discoveryCard
                            dataMaintenanceCard
                        }
                    }
                }
                .padding(.horizontal, 40)
                
                // Footer
                VStack(spacing: 6) {
                    Text("MediaTracker v\(appVersion)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Text("Designed with ❤️ for cinematic tracking.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 60)
            }
            .frame(maxWidth: 1200) // Optimal width for readability
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in containerWidth = newValue }
            }
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
        .fontDesign(.rounded)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "5.0.0"
    }

    // MARK: - Cards
    
    private var appearanceCard: some View {
        SettingsCard(title: "Appearance", icon: "paintpalette.fill", color: .pink) {
            SettingsRow(title: "Accent Color", subtitle: "Hue personality.") {
                HStack(spacing: 8) {
                    ForEach(AppAccent.allCases) { accent in
                        Circle()
                            .fill(accent.color)
                            .frame(width: 18, height: 18)
                            .overlay {
                                if appAccent == accent {
                                    Circle()
                                        .stroke(Color.primary, lineWidth: 1.5)
                                        .frame(width: 26, height: 26)
                                }
                            }
                            .onTapGesture { 
                                withAnimation(.smooth) { appAccent = accent }
                                FeedbackManager.shared.trigger(.click)
                            }
                    }
                }
                .frame(height: 26)
            }
            
            Divider()
            
            SettingsRow(title: "Glass Material", subtitle: "Transparency effects.") {
                Toggle("", isOn: Binding(
                    get: { themeStyle == .brand },
                    set: { themeStyle = $0 ? .brand : .standard }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            Divider()

            SettingsRow(title: "UI Theme", subtitle: "System mode.") {
                Picker("", selection: $themePreference) {
                    Text("Auto").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                .labelsHidden()
                .frame(width: 90)
            }
        }
    }
    
    private var generalCard: some View {
        SettingsCard(title: "General", icon: "gearshape.fill", color: .gray) {
            SettingsRow(title: "Haptic Feedback", subtitle: "Tactile clicks.") {
                Toggle("", isOn: $hapticsEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            
            Divider()
            
            SettingsRow(title: "Audio Feedback", subtitle: "Action sounds.") {
                Toggle("", isOn: $audioEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            
            Divider()

            SettingsRow(title: "Prevent Sleep Mode", subtitle: "Keep background sync active.") {
                Toggle("", isOn: $preventSleepMode)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            
            Divider()

            SettingsRow(title: "Auto-Mark Completed", subtitle: "Mark episodes watched on completion.") {
                Toggle("", isOn: $autoMarkEpisodesWatched)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            
            Divider()
            
            SettingsRow(title: "Notifications", subtitle: "Alert permissions.") {
                Button("Open Preferences") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
    
    private var connectivityCard: some View {
        SettingsCard(title: "Connectivity", icon: "network", color: .blue) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TMDB API Key")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Required for movie and series metadata.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Link(destination: URL(string: "https://www.themoviedb.org/settings/api")!) {
                        Label("Get Key", systemImage: "key.fill")
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                
                SecureField("Enter Key", text: $tmdbApiKey)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .font(.system(size: 11, design: .monospaced))
            }
        }
    }
    
    private var discoveryCard: some View {
        SettingsCard(title: "Discovery", icon: "sparkles.tv.fill", color: .orange) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Studio Aliases")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Merge multiple studios into one.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                StudioAliasManagerView()
                
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Content Filtering")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Manage hidden or restricted tags.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                DiscoveryManagementView()
            }
        }
    }
    
    private var dataMaintenanceCard: some View {
        SettingsCard(title: "Data & Maintenance", icon: "wrench.and.screwdriver.fill", color: .green) {
            VStack(alignment: .leading, spacing: 18) {
                SettingsRow(title: "Library Backup", subtitle: "Export or import JSON.") {
                    HStack(spacing: 8) {
                        Button { LibraryImportExportService.shared.exportLibrary(items: allItems) } label: {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 12))
                        }
                        .help("Export Manual Backup")
                        
                        Button { LibraryImportExportService.shared.importLibrary(modelContext: modelContext) } label: {
                            Image(systemName: "square.and.arrow.down").font(.system(size: 12))
                        }
                        .help("Import Backup")
                        
                        Button {
                            let url = URL.applicationSupportDirectory.appendingPathComponent("AutoBackups")
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "folder.fill").font(.system(size: 12))
                        }
                        .help("Open Auto-Backups Folder")
                    }
                    .buttonStyle(.bordered)
                }
                
                Divider()
                
                SettingsRow(title: "Database Repair", subtitle: "Heal relationships.") {
                    Button {
                        DataService.shared.runMaintenance(modelContext: modelContext)
                    } label: {
                        if DataService.shared.isRunningMaintenance {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Start Repair")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(DataService.shared.isRunningMaintenance)
                }
                
                Divider()
                
                SettingsRow(title: "Image Cache", subtitle: "Full purge.") {
                    Button("Purge Everything") {
                        ImageCache.shared.clearFullCache()
                        FeedbackManager.shared.trigger(.removeFromLibrary)
                        AppErrorState.shared.showToast("Image Cache Cleared", systemImage: "photo.fill", type: .success)
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
                
                Divider()
                
                SettingsRow(title: "Network Cache", subtitle: "Clear responses.") {
                    Button("Clear Cache") {
                        URLCache.shared.removeAllCachedResponses()
                        FeedbackManager.shared.trigger(.removeFromLibrary)
                        AppErrorState.shared.showToast("Network Cache Cleared", systemImage: "wifi.circle.fill", type: .success)
                    }
                    .buttonStyle(.bordered)
                }
                
                Divider()
                
                SettingsRow(title: "Reset Everything", subtitle: "Clear all data.") {
                    Button("Clear Database") {
                        showClearDatabaseConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
                .confirmationDialog(
                    "Are you absolutely sure?",
                    isPresented: $showClearDatabaseConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete All Library Data", role: .destructive) {
                        DataService.shared.clearDatabase(modelContext: modelContext)
                        FeedbackManager.shared.trigger(.removeFromLibrary)
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will permanently delete all your tracked movies, TV shows, and custom settings. This action cannot be undone.")
                }
            }
        }
    }
}

// MARK: - Components

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(color.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .padding(20)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(20)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.03), radius: 10, x: 0, y: 5)
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content
    
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }
    
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 20)
            content
        }
    }
}
