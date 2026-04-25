import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MediaItem.title) private var allItems: [MediaItem]
    @AppStorage("tmdb_api_key") private var tmdbApiKey = ""
    @AppStorage("theme_style") private var themeStyle: ThemeStyle = .standard
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    @AppStorage("theme_preference") private var themePreference: Int = 0 
    @Environment(\.colorScheme) var colorScheme
    
    @State private var activeTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case discovery = "Discovery"
        case library = "Library"
        case advanced = "Advanced"
        
        var id: String { self.rawValue }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .discovery: return "sparkles.tv"
            case .library: return "tray.full"
            case .advanced: return "hammer"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // macOS Style Centered Toolbar
                VStack(spacing: 12) {
                    Text(activeTab.rawValue)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 16) {
                        ForEach(SettingsTab.allCases) { tab in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    activeTab = tab
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    let isSelected = activeTab == tab
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 18))
                                        .frame(width: 32, height: 32)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(Color.primary.opacity(isSelected ? 0.1 : 0), lineWidth: 0.5)
                                        )
                                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                    
                                    Text(tab.rawValue)
                                        .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                                        .foregroundStyle(isSelected ? .primary : .secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
                .background(Material.thin)
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        switch activeTab {
                        case .general:
                            generalSettings
                        case .discovery:
                            discoverySettings
                        case .library:
                            librarySettings
                        case .advanced:
                            advancedSettings
                        }
                        
                        // App Info
                        VStack(spacing: 4) {
                            Text("MediaTracker v2.5.0")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.tertiary)
                            Text("Designed for macOS")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    }
                    .padding(24)
                }
                .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
            }
        }
        .frame(width: 480, height: 560)
        .fontDesign(.rounded)
        .alert("Repair Complete", isPresented: Binding(
            get: { DataService.shared.showMaintenanceComplete },
            set: { DataService.shared.showMaintenanceComplete = $0 }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your library has been healed and unique identifiers assigned.")
        }
    }
    
    // MARK: - Sections
    
    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Appearance") {
                SettingsRow(title: "Accent Color", subtitle: "Personalize the app's primary hue.") {
                    HStack(spacing: 10) {
                        ForEach(AppAccent.allCases) { accent in
                            Circle()
                                .fill(accent.color)
                                .frame(width: 14, height: 14)
                                .overlay {
                                    if appAccent == accent {
                                        Circle()
                                            .stroke(Color.primary, lineWidth: 2)
                                            .frame(width: 22, height: 22)
                                    }
                                }
                                .onTapGesture { appAccent = accent }
                        }
                    }
                }
                
                Divider()
                
                SettingsRow(title: "Brand Tints", subtitle: "Enable dynamic glass background effects.") {
                    Toggle("", isOn: Binding(
                        get: { themeStyle == .brand },
                        set: { themeStyle = $0 ? .brand : .standard }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                Divider()

                SettingsRow(title: "Theme Mode", subtitle: "Switch between light and dark UI.") {
                    Picker("", selection: $themePreference) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
            }
        }
    }
    
    private var discoverySettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Content Filtering") {
                DiscoveryManagementView()
            }
        }
    }
    
    private var librarySettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "API Services") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TMDB API Key")
                                .font(.system(size: 13, weight: .medium))
                            Text("Required for movie and series metadata.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Link("Get Key", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                            .font(.system(size: 11, weight: .bold))
                    }
                    
                    SecureField("Required", text: $tmdbApiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
            }
            
            SettingsSection(title: "Library Management") {
                SettingsRow(title: "Backup & Restore", subtitle: "Export your history or import a JSON backup.") {
                    HStack(spacing: 8) {
                        Button { DataService.shared.exportLibrary(items: allItems) } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button { DataService.shared.importLibrary(modelContext: modelContext) } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Divider()
                
                SettingsRow(title: "Database Repair", subtitle: "Fix identifiers and remove duplicate entries.") {
                    Button {
                        DataService.shared.runMaintenance(modelContext: modelContext)
                    } label: {
                        if DataService.shared.isRunningMaintenance {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Run")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(DataService.shared.isRunningMaintenance)
                }
            }
        }
    }
    
    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 32) {
            tuningSection
            
            SettingsSection(title: "Diagnostics") {
                SettingsRow(title: "Test Notifications", subtitle: "Verify alert permissions and rich actions.") {
                    Button("Send Test") {
                        NotificationManager.shared.sendTestNotification()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // NEW: Algorithmic Tuning in Settings
    @State private var wGenre = 30.0
    @State private var wCreator = 30.0
    @State private var wLang = 10.0
    @State private var wCast = 5.0
    @State private var wNetwork = 5.0
    @State private var hasUnsavedTuning = false

    @AppStorage("taste_weight_genre") private var storedWGenre = 30.0
    @AppStorage("taste_weight_creator") private var storedWCreator = 30.0
    @AppStorage("taste_weight_lang") private var storedWLang = 10.0
    @AppStorage("taste_weight_cast") private var storedWCast = 5.0
    @AppStorage("taste_weight_network") private var storedWNetwork = 5.0

    private var tuningSection: some View {
        SettingsSection(title: "Algorithm Tuning") {
            VStack(spacing: 16) {
                Text("Adjust how much each factor influences your 'For You' recommendations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)

                tuningSlider(label: "Genres", value: $wGenre, color: .purple)
                tuningSlider(label: "Directors", value: $wCreator, color: .blue)
                tuningSlider(label: "Language", value: $wLang, color: .green)
                tuningSlider(label: "Cast", value: $wCast, color: .orange)
                
                HStack {
                    Spacer()
                    if hasUnsavedTuning {
                        Button("Apply Changes") {
                            applyTuning()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(appAccent.color)
                        .controlSize(.small)
                    }
                }
            }
        }
        .onAppear {
            wGenre = storedWGenre
            wCreator = storedWCreator
            wLang = storedWLang
            wCast = storedWCast
            wNetwork = storedWNetwork
            hasUnsavedTuning = false
        }
    }

    @ViewBuilder
    private func tuningSlider(label: String, value: Binding<Double>, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Text("\(Int(value.wrappedValue))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...100, step: 5)
                .tint(color)
                .onChange(of: value.wrappedValue) { _, _ in hasUnsavedTuning = true }
        }
    }

    private func applyTuning() {
        storedWGenre = wGenre
        storedWCreator = wCreator
        storedWLang = wLang
        storedWCast = wCast
        storedWNetwork = wNetwork
        hasUnsavedTuning = false
        NotificationCenter.default.post(name: .tasteWeightsChanged, object: nil)
        AppErrorState.shared.surfaceError("Algorithm Updated", systemImage: "sparkles")
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
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
            
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
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
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 20)
            content
        }
    }
}

struct DiscoveryManagementView: View {
    @Query(sort: \NetworkEntity.name) private var networkEntities: [NetworkEntity]
    @AppStorage("hidden_studios") private var hiddenStudios: String = ""
    @State private var availableNetworks: [String] = []
    
    private var hiddenList: [String] {
        hiddenStudios.components(separatedBy: ",").filter { !$0.isEmpty }.sorted()
    }
    
    private var addableNetworks: [String] {
        availableNetworks.filter { !hiddenList.contains($0) }.sorted()
    }

    @State private var isAddPopoverPresented = false
    @State private var networkSearchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Hidden Networks")
                    .font(.system(size: 13, weight: .medium))
                
                Spacer()
                
                Button {
                    isAddPopoverPresented.toggle()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $isAddPopoverPresented, arrowEdge: .bottom) {
                    VStack(spacing: 0) {
                        TextField("Search networks...", text: $networkSearchText)
                            .textFieldStyle(.roundedBorder)
                            .padding(12)
                        
                        Divider()
                        
                        ScrollView {
                            VStack(spacing: 0) {
                                let filtered = addableNetworks.filter { 
                                    networkSearchText.isEmpty || $0.localizedCaseInsensitiveContains(networkSearchText) 
                                }
                                
                                if filtered.isEmpty {
                                    Text("No matches").font(.caption).padding(.vertical, 20)
                                } else {
                                    ForEach(filtered, id: \.self) { name in
                                        Button {
                                            toggleHidden(name)
                                            isAddPopoverPresented = false
                                        } label: {
                                            Text(name)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .frame(height: 180)
                    }
                    .frame(width: 200)
                }
            }
            
            VStack(spacing: 0) {
                if hiddenList.isEmpty {
                    Text("All networks are visible")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    ForEach(hiddenList, id: \.self) { name in
                        HStack {
                            Text(name)
                                .font(.system(size: 13))
                            Spacer()
                            Button { toggleHidden(name) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        
                        if name != hiddenList.last {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onAppear { calculateNetworks() }
    }
    
    private func toggleHidden(_ name: String) {
        var hidden = hiddenStudios.components(separatedBy: ",").filter { !$0.isEmpty }
        if let index = hidden.firstIndex(of: name) {
            hidden.remove(at: index)
        } else {
            hidden.append(name)
        }
        hiddenStudios = hidden.joined(separator: ",")
    }

    private func calculateNetworks() {
        availableNetworks = networkEntities.map { $0.name }.sorted()
    }
}
