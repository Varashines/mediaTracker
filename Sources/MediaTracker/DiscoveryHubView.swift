import SwiftUI
import SwiftData

struct DiscoveryHubView: View {
    let items: [MediaItem]
    let namespace: Namespace.ID
    @Bindable var viewModel: MediaViewModel
    var onFilterSelected: (DiscoveryFilter) -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isRefreshing = false
    @AppStorage("hidden_studios") private var hiddenStudios: String = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 50) {
                // Header
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Media Galaxy")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("Explore your collection as an organic cluster.")
                            .font(.subheadline)
                            .fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        refreshData(force: true)
                    } label: {
                        HStack {
                            if isRefreshing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Refresh")
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                }
                .padding(.horizontal, 30)
                
                // 1. Studios & Networks Section
                VStack(alignment: .leading, spacing: 15) {
                    Text("Studios & Networks")
                        .font(.title2.bold())
                        .fontDesign(.rounded)
                        .padding(.horizontal, 30)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 20)], spacing: 20) {
                        ForEach(viewModel.cachedNetworks) { network in
                            Button {
                                onFilterSelected(DiscoveryFilter(type: .studio, name: network.name))
                            } label: {
                                HubTile(node: network, icon: "tv.fill", accentColor: .indigo, isLogoType: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 30)
                }
                
                // 2. Languages Section
                VStack(alignment: .leading, spacing: 15) {
                    Text("Languages")
                        .font(.title2.bold())
                        .fontDesign(.rounded)
                        .padding(.horizontal, 30)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 20)], spacing: 20) {
                        ForEach(viewModel.cachedLanguages) { language in
                            Button {
                                onFilterSelected(DiscoveryFilter(type: .language, name: language.name))
                            } label: {
                                let displayName = languageName(for: language.name)
                                let displayNode = DiscoveryNode(name: displayName, logoPath: nil, count: language.count)
                                HubTile(node: displayNode, icon: "character.bubble.fill", accentColor: .indigo, isLogoType: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 30)
                }
                
                // 3. Genres Section
                VStack(alignment: .leading, spacing: 15) {
                    Text("Genres")
                        .font(.title2.bold())
                        .fontDesign(.rounded)
                        .padding(.horizontal, 30)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 20)], spacing: 20) {
                        ForEach(viewModel.cachedGenres) { genre in
                            Button {
                                onFilterSelected(DiscoveryFilter(type: .genre, name: genre.name))
                            } label: {
                                HubTile(node: genre, icon: "tag.fill", accentColor: .indigo, isLogoType: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 30)
                }
            }
            .padding(.vertical, 30)
            .background {
                ZStack {
                    Circle()
                        .fill(Color.pink.opacity(colorScheme == .dark ? 0.08 : 0.04))
                        .frame(width: 400, height: 400)
                        .blur(radius: 80)
                        .offset(x: 200, y: -300)
                    
                    Circle()
                        .fill(Color.teal.opacity(colorScheme == .dark ? 0.08 : 0.04))
                        .frame(width: 400, height: 400)
                        .blur(radius: 80)
                        .offset(x: -200, y: 300)
                }
            }
        }
        .onAppear {
            refreshData(force: false)
        }
        .onChange(of: hiddenStudios) {
            refreshData(force: true)
        }
    }
    
    private func refreshData(force: Bool) {
        // Only refresh if forced or if never refreshed or if older than 24 hours
        let twentyFourHours: TimeInterval = 24 * 60 * 60
        let needsRefresh = viewModel.lastDiscoveryRefresh == nil || 
                          Date().timeIntervalSince(viewModel.lastDiscoveryRefresh!) > twentyFourHours
        
        guard force || needsRefresh else { return }
        
        isRefreshing = true
        
        // Use a background task for the heavy scanning
        Task.detached(priority: .userInitiated) {
            let (networks, genres, languages) = await calculateDiscoveryData()
            
            await MainActor.run {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    viewModel.cachedNetworks = networks
                    viewModel.cachedGenres = genres
                    viewModel.cachedLanguages = languages
                    viewModel.lastDiscoveryRefresh = Date()
                    isRefreshing = false
                }
            }
        }
    }
    
    private func calculateDiscoveryData() async -> (networks: [DiscoveryNode], genres: [DiscoveryNode], languages: [DiscoveryNode]) {
        var networkMap: [String: String] = [:]
        var networkCounts: [String: Int] = [:]
        var genreCounts: [String: Int] = [:]
        var languageCounts: [String: Int] = [:]
        
        let hiddenSet = Set(hiddenStudios.components(separatedBy: ",").filter { !$0.isEmpty })
        
        for item in items {
            // 1. Networks (Strictly TV Only)
            if item.type == .tvShow, let tv = item.tvShowDetails, let name = tv.network {
                if networkMap[name] == nil || (networkMap[name] == "" && tv.networkLogoPath != nil) {
                    networkMap[name] = tv.networkLogoPath ?? ""
                }
                networkCounts[name, default: 0] += 1
            }
            
            // 2. Genres (All items)
            for genre in item.genres {
                genreCounts[genre, default: 0] += 1
            }
            
            // 3. Languages (All items)
            let lang = (item.type == .movie ? item.movieDetails?.originalLanguage : item.tvShowDetails?.originalLanguage)
            if let lang = lang {
                languageCounts[lang, default: 0] += 1
            }
        }
        
        let networks: [DiscoveryNode] = networkMap.compactMap { (name: String, logo: String) -> DiscoveryNode? in
            guard !hiddenSet.contains(name) else { return nil }
            return DiscoveryNode(name: name, logoPath: logo.isEmpty ? nil : logo, count: networkCounts[name] ?? 0)
        }.sorted { $0.count > $1.count }
        
        let genres: [DiscoveryNode] = genreCounts.map { (key: String, value: Int) -> DiscoveryNode in
            DiscoveryNode(name: key, logoPath: nil, count: value)
        }.sorted { $0.count > $1.count }
            
        let languages: [DiscoveryNode] = languageCounts.map { (key: String, value: Int) -> DiscoveryNode in
            DiscoveryNode(name: key, logoPath: nil, count: value)
        }.sorted { $0.count > $1.count }
            
        return (networks, genres, languages)
    }
    
    private func languageName(for code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }
}

struct HubTile: View {
    let node: DiscoveryNode
    let icon: String
    let accentColor: Color
    var isLogoType: Bool = true
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme
    @State private var manager = NetworkThemeManager.shared
    
    private var displayAccentColor: Color {
        if isLogoType, let cached = manager.color(for: node.name) {
            return cached
        }
        return accentColor
    }
    
    var body: some View {
        ZStack {
            // Flattened Liquid Glass Surface
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 8,
                bottomTrailingRadius: 24,
                topTrailingRadius: 8,
                style: .continuous
            )
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                .overlay {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 24,
                        bottomLeadingRadius: 8,
                        bottomTrailingRadius: 24,
                        topTrailingRadius: 8,
                        style: .continuous
                    )
                        .stroke(
                            LinearGradient(
                                colors: [
                                    displayAccentColor.opacity(isHovered ? 0.8 : 0.4),
                                    .clear,
                                    displayAccentColor.opacity(isHovered ? 0.3 : 0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                }
                .background {
                    // Subtle tint instead of heavy material
                    UnevenRoundedRectangle(
                        topLeadingRadius: 24,
                        bottomLeadingRadius: 8,
                        bottomTrailingRadius: 24,
                        topTrailingRadius: 8,
                        style: .continuous
                    )
                        .fill(displayAccentColor.opacity(colorScheme == .dark ? 0.15 : 0.08))
                }
            
            // Content layer
            ZStack {
                if isLogoType {
                    if let path = node.logoPath, let url = URL(string: "https://image.tmdb.org/t/p/w185\(path)") {
                        CachedImage(url: url) { image in
                            // Extract color if not already cached
                            if manager.themeMap[node.name] == nil {
                                let container = ImageContainer(image: image)
                                Task.detached(priority: .background) {
                                    let dominant = ColorExtractor.dominantColor(from: container.image)
                                    await MainActor.run {
                                        manager.save(color: dominant, for: node.name)
                                    }
                                }
                            }
                        } placeholder: {
                            Text(node.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                        }
                        .aspectRatio(contentMode: .fit)
                        .padding(15)
                        .opacity(isHovered ? 0 : 1)
                        .scaleEffect(isHovered ? 0.9 : 1)
                    } else {
                        Text(node.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 15)
                            .opacity(isHovered ? 0 : 1)
                            .scaleEffect(isHovered ? 0.9 : 1)
                    }
                }
                
                if !isLogoType || isHovered {
                    VStack(spacing: 4) {
                        Text(node.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 15)
                        
                        if isHovered {
                            Text("\(node.count) \(node.count == 1 ? "item" : "items")")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .opacity(!isLogoType || isHovered ? 1 : 0)
                }
            }
        }
        .frame(height: 90)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: displayAccentColor.opacity(isHovered ? 0.2 : 0.05), radius: isHovered ? 10 : 0, y: isHovered ? 5 : 0) // No shadow when not hovered
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
