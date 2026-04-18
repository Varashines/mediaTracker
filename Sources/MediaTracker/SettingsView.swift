import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MediaItem.title) private var allItems: [MediaItem]
    @AppStorage("tmdb_api_key") private var tmdbApiKey = ""
    @AppStorage("theme_style") private var themeStyle: ThemeStyle = .standard
    @AppStorage("app_accent") private var appAccent: AppAccent = .indigo
    @AppStorage("theme_preference") private var themePreference: Int = 0 // 0: System, 1: Light, 2: Dark
    @AppStorage("now_watching_days") private var nowWatchingDays: Int = 2
    @Environment(\.colorScheme) var colorScheme
    
    @State private var activeTab: SettingsTab = .preferences

    enum SettingsTab: String, CaseIterable, Identifiable {
        case preferences = "General"
        case tvDiscovery = "Discovery"
        
        var id: String { self.rawValue }
        var icon: String {
            switch self {
            case .preferences: return "gearshape.fill"
            case .tvDiscovery: return "sparkles.tv.fill"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // macOS Style Toolbar
            HStack(spacing: 0) {
                Spacer()
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            activeTab = tab
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(activeTab == tab ? appAccent.color : .secondary)
                                .frame(width: 34, height: 34)
                                .background {
                                    if activeTab == tab {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(appAccent.color.opacity(0.12))
                                    }
                                }
                            
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: activeTab == tab ? .semibold : .medium))
                                .foregroundStyle(activeTab == tab ? .primary : .secondary)
                        }
                        .frame(width: 70)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Content Area
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch activeTab {
                    case .preferences:
                        preferencesContent
                    case .tvDiscovery:
                        DiscoveryManagementView()
                    }
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
        .frame(width: 440, height: 480)
        .fontDesign(.rounded)
    }
    
    private var preferencesContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "APPEARANCE") {
                SettingsRow(title: "Accent Color", subtitle: "Personalize the app's primary hue.") {
                    HStack(spacing: 10) {
                        ForEach(AppAccent.allCases) { accent in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    appAccent = accent
                                }
                            } label: {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 14, height: 14)
                                    .overlay {
                                        if appAccent == accent {
                                            Circle()
                                                .stroke(Color.primary.opacity(0.5), lineWidth: 2)
                                                .frame(width: 22, height: 22)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(height: 24)
                    .padding(.trailing, 4)
                }
                
                Divider()
                
                SettingsRow(title: "Brand Theme", subtitle: "Use the selected accent for background tints.") {
                    Toggle("", isOn: Binding(
                        get: { themeStyle == .brand },
                        set: { isBrand in themeStyle = isBrand ? .brand : .standard }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                Divider()

                SettingsRow(title: "App Theme", subtitle: "Choose between system, light, or dark mode.") {
                    Toggle("System", isOn: Binding(
                        get: { themePreference == 0 },
                        set: { newValue in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if newValue {
                                    themePreference = 0
                                } else {
                                    // Robust check for the effective system appearance
                                    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                                    themePreference = isDark ? 2 : 1
                                }
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                if themePreference != 0 {
                    HStack(spacing: 12) {
                        ThemePill(title: "Light", isSelected: themePreference == 1, accent: appAccent, mode: .light) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                themePreference = 1
                            }
                        }
                        ThemePill(title: "Dark", isSelected: themePreference == 2, accent: appAccent, mode: .dark) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                themePreference = 2
                            }
                        }
                    }
                    .padding(.top, 4)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                }

                Divider()

                SettingsRow(title: "Now Watching Window", subtitle: "Number of days to keep active titles in the 'Now Watching' section.") {
                    HStack(spacing: 8) {
                        Text("\(nowWatchingDays) \(nowWatchingDays == 1 ? "day" : "days")")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        Stepper("", value: $nowWatchingDays, in: 1...14)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                }
            }
            
            SettingsGroup(title: "SERVICES") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TMDB API Key")
                                .font(.system(size: 13, weight: .medium))
                            Text("Required to fetch movies and TV show metadata.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Link(destination: URL(string: "https://www.themoviedb.org/settings/api")!) {
                            Text("Get Key")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    SecureField("Required", text: $tmdbApiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
                }
            }
            
            SettingsGroup(title: "DATA MANAGEMENT") {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Library Portability")
                            .font(.system(size: 13, weight: .medium))
                        Text("Export your watch history or import a backup.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 8) {
                        Button { DataService.shared.exportLibrary(items: allItems) } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        
                        Button { DataService.shared.importLibrary(modelContext: modelContext) } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.small)
                }
            }
            
            SettingsGroup(title: "ADVANCED") {
                SettingsRow(title: "Notifications", subtitle: "Test local alerts to verify permissions.") {
                    Button {
                        NotificationManager.shared.sendTestNotification()
                    } label: {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.indigo)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            VStack(alignment: .center, spacing: 4) {
                Text("MediaTracker v2.4")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("Designed with Love")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
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
            Spacer()
            content
        }
    }
}

struct DiscoveryManagementView: View {
    @Query(sort: \MediaItem.title) private var items: [MediaItem]
    @AppStorage("hidden_studios") private var hiddenStudios: String = ""
    @State private var availableNetworks: [String] = []
    @Environment(\.colorScheme) var colorScheme
    
    private var hiddenList: [String] {
        hiddenStudios.components(separatedBy: ",").filter { !$0.isEmpty }.sorted()
    }
    
    private var addableNetworks: [String] {
        availableNetworks.filter { !hiddenList.contains($0) }.sorted()
    }

    @State private var isAddPopoverPresented = false
    @State private var networkSearchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("HIDDEN NETWORKS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if !addableNetworks.isEmpty {
                    Button {
                        isAddPopoverPresented.toggle()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 20, height: 20)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isAddPopoverPresented, arrowEdge: .bottom) {
                        VStack(spacing: 0) {
                            TextField("Search networks...", text: $networkSearchText)
                                .textFieldStyle(.plain)
                                .padding(8)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(6)
                                .padding(10)
                            
                            Divider()
                            
                            ScrollView {
                                VStack(spacing: 0) {
                                    let filtered = addableNetworks.filter { 
                                        networkSearchText.isEmpty || $0.localizedCaseInsensitiveContains(networkSearchText) 
                                    }
                                    
                                    if filtered.isEmpty {
                                        Text("No matches")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                            .padding(.vertical, 20)
                                    } else {
                                        ForEach(filtered, id: \.self) { name in
                                            Button {
                                                toggleHidden(name)
                                                isAddPopoverPresented = false
                                                networkSearchText = ""
                                            } label: {
                                                HStack {
                                                    Text(name)
                                                        .font(.system(size: 12))
                                                    Spacer()
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            
                                            if name != filtered.last {
                                                Divider().padding(.horizontal, 8)
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(height: 200)
                        }
                        .frame(width: 200)
                    }
                }
            }
            .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                if hiddenList.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "eye")
                            .font(.system(size: 20))
                            .foregroundStyle(.tertiary)
                        Text("All networks are visible")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(hiddenList, id: \.self) { name in
                        HStack {
                            Text(name)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    toggleHidden(name)
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        
                        if name != hiddenList.last {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            
            HStack {
                Button("Reset to Defaults") {
                    withAnimation { hiddenStudios = "" }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
                
                Text("\(hiddenList.count) hidden")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
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
        var names: Set<String> = []
        for item in items where item.type == .tvShow {
            if let tv = item.tvShowDetails, let name = tv.network { names.insert(name) }
        }
        availableNetworks = Array(names).sorted()
    }
}

struct ThemePill: View {
    let title: String
    let isSelected: Bool
    let accent: AppAccent
    let mode: ColorScheme
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .foregroundStyle(mode == .dark ? Color.white : Color.black)
                .opacity(isSelected ? 1.0 : 0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accent.brandBackground(for: mode))
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(accent.color.opacity(0.8), lineWidth: 2)
                            } else {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                            }
                        }
                }
        }
        .buttonStyle(.plain)
    }
}
