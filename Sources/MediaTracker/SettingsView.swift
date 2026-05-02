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
    
    @Environment(\.colorScheme) var colorScheme
    @State private var activeTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case appearance = "Appearance"
        case library = "Library"
        case discovery = "Discovery"
        
        var id: String { self.rawValue }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .appearance: return "paintpalette"
            case .library: return "tray.full"
            case .discovery: return "sparkles.tv"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // "Spacey" Centered Top Navigation
            VStack(spacing: 20) {
                HStack(spacing: 32) {
                    ForEach(SettingsTab.allCases) { tab in
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                activeTab = tab
                            }
                            FeedbackManager.shared.trigger(.click)
                        } label: {
                            VStack(spacing: 6) {
                                let isSelected = activeTab == tab
                                Image(systemName: tab.icon)
                                    .font(.system(size: 20, weight: isSelected ? .bold : .medium))
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle()
                                            .fill(isSelected ? appAccent.color.opacity(0.1) : Color.clear)
                                    )
                                    .foregroundStyle(isSelected ? appAccent.color : .secondary)
                                    .scaleEffect(isSelected ? 1.1 : 1.0)
                                
                                Text(tab.rawValue)
                                    .font(.system(size: 11, weight: isSelected ? .black : .semibold))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                                    .kerning(0.5)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 24)
                
                // Active Header
                VStack(spacing: 4) {
                    Text(activeTab.rawValue)
                        .font(.system(size: 24, weight: .black))
                    Text(subtitle(for: activeTab))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(activeTab) // Trigger transition on tab change
            }
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    switch activeTab {
                    case .general:
                        generalSettings
                    case .appearance:
                        appearanceSettings
                    case .library:
                        librarySettings
                    case .discovery:
                        discoverySettings
                    }
                    
                    // Footer Info
                    VStack(spacing: 6) {
                        Text("MediaTracker v2.7.0")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.tertiary)
                        Text("Spacey, Profesh, and Cute.")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
                .padding(40)
            }
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
        .frame(width: 600, height: 700)
        .fontDesign(.rounded)
    }

    private func subtitle(for tab: SettingsTab) -> String {
        switch tab {
        case .general: return "Core behavior and interaction settings."
        case .appearance: return "Personalize your visual experience."
        case .library: return "Data management and API connectivity."
        case .discovery: return "Fine-tune your browsing filters."
        }
    }
    
    // MARK: - Sections
    
    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Interactions") {
                SettingsRow(title: "Haptic Feedback", subtitle: "Tactile clicks on supported trackpads.") {
                    Toggle("", isOn: $hapticsEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                
                Divider()
                
                SettingsRow(title: "Audio Feedback", subtitle: "Play subtle sounds for key actions.") {
                    Toggle("", isOn: $audioEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
            
            SettingsSection(title: "System") {
                SettingsRow(title: "Notifications", subtitle: "Manage system-level alert permissions.") {
                    Button("Open Preferences...") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Customization") {
                SettingsRow(title: "Accent Color", subtitle: "Your app's personality hue.") {
                    HStack(spacing: 12) {
                        ForEach(AppAccent.allCases) { accent in
                            Circle()
                                .fill(accent.color)
                                .frame(width: 20, height: 20)
                                .overlay {
                                    if appAccent == accent {
                                        Circle()
                                            .stroke(Color.primary, lineWidth: 2)
                                            .frame(width: 30, height: 30)
                                    }
                                }
                                .onTapGesture { 
                                    appAccent = accent 
                                    FeedbackManager.shared.trigger(.click)
                                }
                        }
                    }
                    .frame(height: 34)
                }
                
                Divider()
                
                SettingsRow(title: "Glass Material", subtitle: "Enable dynamic transparency effects.") {
                    Toggle("", isOn: Binding(
                        get: { themeStyle == .brand },
                        set: { themeStyle = $0 ? .brand : .standard }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                Divider()

                SettingsRow(title: "UI Theme", subtitle: "Switch between light and dark modes.") {
                    Picker("", selection: $themePreference) {
                        Text("Auto").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }
        }
    }
    
    private var discoverySettings: some View {
        VStack(alignment: .leading, spacing: 32) {
            SettingsSection(title: "Studio Aliases") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Merge multiple studios into one and pick an icon.")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    StudioAliasManagerView()
                    
                    Text("Changes apply after the next Discovery refresh.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            SettingsSection(title: "Content Filtering") {
                DiscoveryManagementView()
            }
        }
    }
    
    private var librarySettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Connectivity") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TMDB API Key")
                                .font(.system(size: 13, weight: .bold))
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
                        .padding(12)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .font(.system(size: 12, design: .monospaced))
                }
            }
            
            SettingsSection(title: "Data Management") {
                SettingsRow(title: "Backup & Portability", subtitle: "Export or import your library data.") {
                    HStack(spacing: 12) {
                        Button { DataService.shared.exportLibrary(items: allItems) } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        Button { DataService.shared.importLibrary(modelContext: modelContext) } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                Divider()
                
                SettingsRow(title: "Maintenance", subtitle: "Repair database and purge duplicates.") {
                    VStack(alignment: .trailing, spacing: 8) {
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
                        
                        Button {
                            DataService.shared.refreshAllBadges(modelContext: modelContext)
                        } label: {
                            Text("Recalculate Badges")
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            URLCache.shared.removeAllCachedResponses()
                            FeedbackManager.shared.trigger(.removeFromLibrary)
                            AppErrorState.shared.showToast("Network Cache Cleared", systemImage: "wifi.circle.fill", type: .success)
                        } label: {
                            Text("Clear Network Cache")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            SettingsSection(title: "Image Cache") {
                SettingsRow(title: "Storage Cleanup", subtitle: "Force a full refresh of all posters.") {
                    Button("Purge Everything") {
                        ImageCache.shared.clearFullCache()
                        FeedbackManager.shared.trigger(.removeFromLibrary)
                        AppErrorState.shared.showToast("Image Cache Cleared", systemImage: "photo.fill", type: .success)
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
            }
        }
    }
}

// MARK: - Reusable Components

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .kerning(1.5)
            
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.02), radius: 10, x: 0, y: 5)
        }
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
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 40)
            content
        }
    }
}
