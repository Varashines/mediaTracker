import SwiftUI
import SwiftData

struct DiscoveryHubView: View {
    @Environment(\.modelContext) private var modelContext
    let namespace: Namespace.ID
    @Bindable var viewModel: MediaViewModel
    let onFilterSelected: (DiscoveryFilter) -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    @AppStorage("hidden_studios") private var hiddenStudios: String = ""
    
    // Performance: Local state to prevent "View Pop-in"
    @State private var hasDataLoaded = false

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]
        
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                // 1. Studios
                if !viewModel.cachedNetworks.isEmpty {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Studios")
                            .font(.title3.bold())
                            .fontDesign(.rounded)
                            .padding(.horizontal, 30)
                        
                        LazyVGrid(columns: columns, spacing: 20) {
                            let nets = viewModel.cachedNetworks
                            ForEach(nets.indices, id: \.self) { idx in
                                Button {
                                    onFilterSelected(DiscoveryFilter(type: .studio, name: nets[idx].name))
                                } label: {
                                    UltraNetworkTile(network: nets[idx], staggerIndex: idx)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 30)
                        .padding(.vertical, 10)
                    }
                }
                
                // 3. Languages
                if !viewModel.cachedLanguages.isEmpty {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("World Languages")
                            .font(.title3.bold())
                            .fontDesign(.rounded)
                            .padding(.horizontal, 30)
                        
                        LazyVGrid(columns: columns, spacing: 20) {
                            let langs = viewModel.cachedLanguages
                            ForEach(langs.indices, id: \.self) { idx in
                                Button {
                                    onFilterSelected(DiscoveryFilter(type: .language, name: langs[idx].code ?? langs[idx].name))
                                } label: {
                                    UltraPillTile(item: langs[idx], icon: "character.bubble.fill", color: appAccent.color, staggerIndex: idx)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 30)
                        .padding(.vertical, 10)
                    }
                }
                
                // 4. Genres
                if !viewModel.cachedGenres.isEmpty {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Explore Genres")
                            .font(.title3.bold())
                            .fontDesign(.rounded)
                            .padding(.horizontal, 30)
                        
                        LazyVGrid(columns: columns, spacing: 20) {
                            let genres = viewModel.cachedGenres
                            ForEach(genres.indices, id: \.self) { idx in
                                Button {
                                    onFilterSelected(DiscoveryFilter(type: .genre, name: genres[idx].name))
                                } label: {
                                    UltraPillTile(item: genres[idx], icon: "tag.fill", color: appAccent.color, staggerIndex: idx)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 30)
                        .padding(.vertical, 10)
                    }
                }
            }
            .padding(.vertical, 40)
        }
        .scrollClipDisabled()
        .background(Color.clear)
        .onAppear {
            // Optimization: Only refresh if empty
            if viewModel.cachedNetworks.isEmpty {
                refreshData(force: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tasteWeightsChanged)) { _ in
            refreshData(force: false)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    refreshData(force: true)
                } label: {
                    Label("Force Sync", systemImage: "bolt.fill")
                }
                .help("Re-calculate Discovery metrics")
            }
        }
    }
    
    private func refreshData(force: Bool) {
        let container = modelContext.container
        let localHidden = hiddenStudios
        
        // Phase 4: Ensure persistent actors are initialized on the MainActor
        if force && viewModel.discoverySyncService == nil {
            viewModel.discoverySyncService = DiscoverySyncService(modelContainer: container)
        }
        if viewModel.tasteActor == nil {
            viewModel.tasteActor = TasteActor(modelContainer: container)
        }
        
        let syncService = viewModel.discoverySyncService
        let tasteActor = viewModel.tasteActor

        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            
            // Sync if forced or empty
            if force {
                await syncService?.syncLibrary(force: true)
            }
            
            // Fetch snapshots
            let netDescriptor = FetchDescriptor<NetworkEntity>(sortBy: [SortDescriptor(\.count, order: .reverse)])
            let genreDescriptor = FetchDescriptor<GenreEntity>(sortBy: [SortDescriptor(\.count, order: .reverse)])
            let langDescriptor = FetchDescriptor<LanguageEntity>(sortBy: [SortDescriptor(\.count, order: .reverse)])
            
            let nets = (try? context.fetch(netDescriptor)) ?? []
            let hiddenSet = Set(localHidden.components(separatedBy: ",").filter { !$0.isEmpty })
            let filteredNets = nets.filter { !hiddenSet.contains($0.name) }
            
            let snNets = filteredNets.map { DiscoveryNode(name: $0.name, logoPath: $0.logoPath, count: $0.count, themeColorHex: $0.themeColorHex) }
            let snGenres = ((try? context.fetch(genreDescriptor)) ?? []).map { DiscoveryNode(name: $0.name, logoPath: nil, count: $0.count) }
            let snLangs = ((try? context.fetch(langDescriptor)) ?? []).map { 
                let name = LanguageUtils.languageName(for: $0.code)
                return DiscoveryNode(name: name, code: $0.code, logoPath: nil, count: $0.count) 
            }
            
            // Phase 3 Optimization: NPU-Accelerated Recommendations
            guard let taste = tasteActor else { return }
            let recommendations = await taste.calculateRecommendations()
            let snRecs = recommendations.compactMap { (id, reason) -> MediaThumbnailMetadata? in
                guard let item = context.model(for: id) as? MediaItem else { return nil }
                return MediaThumbnailMetadata(
                    id: item.persistentModelID,
                    title: item.title,
                    posterURL: item.posterURL,
                    backdropURL: item.backdropURL,
                    overview: item.overview,
                    genres: item.cachedGenres,
                    releaseDate: item.releaseDate,
                    state: item.state,
                    type: item.type,
                    taste: item.tasteValue,
                    cachedNextAiringDate: item.cachedNextAiringDate,
                    cachedNetwork: item.cachedNetwork,
                    themeColorHex: item.themeColorHex,
                    badgeText: item.badgeText,
                    watchProgress: item.storedWatchProgressLabel,
                    nextEpisodeToWatchLabel: item.storedNextEpisodeLabel,
                    progress: item.storedProgress,
                    isUpcoming: item.storedIsUpcoming,
                    isBingeDrop: item.storedIsBingeDrop,
                    smartBadgeLabel: item.storedSmartBadgeLabel,
                    smartBadgeIcon: item.storedSmartBadgeIcon,
                    isSparkleBadge: item.storedSmartBadgeIsSparkle,
                    versionHash: item.lastStateChangeDate.hashValue,
                    recommendationReason: reason
                )
            }
            
            await MainActor.run {
                withAnimation(.smooth(duration: 0.5)) {
                    self.viewModel.cachedNetworks = snNets
                    self.viewModel.cachedGenres = snGenres
                    self.viewModel.cachedLanguages = snLangs
                    self.viewModel.forYouRecommendations = snRecs
                    self.hasDataLoaded = true
                }
            }
        }
    }
}

// MARK: - Ultra Lightweight Primitives

struct UltraNetworkTile: View {
    let network: DiscoveryNode
    var staggerIndex: Int? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    @State private var isAppeared = false
    
    var body: some View {
        ZStack {
            let baseColor = network.themeColorHex.flatMap { Color(hex: $0) } ?? .secondary
            
            // Adaptive Glass: Use ThinMaterial on M1 for GPU efficiency
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 8,
                bottomTrailingRadius: 24,
                topTrailingRadius: 8,
                style: .continuous
            )
            .fill(.thinMaterial)
            .opacity(colorScheme == .dark ? 0.8 : 0.4)
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 24,
                    bottomLeadingRadius: 8,
                    bottomTrailingRadius: 24,
                    topTrailingRadius: 8,
                    style: .continuous
                )
                .fill(baseColor.opacity(colorScheme == .dark ? 0.2 : 0.1))
            }
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 24,
                    bottomLeadingRadius: 8,
                    bottomTrailingRadius: 24,
                    topTrailingRadius: 8,
                    style: .continuous
                )
                .stroke(baseColor.opacity(isHovered ? 0.6 : 0.2), lineWidth: 1.5)
            }
            
            // Content Layer with Fade Transition on Hover
            ZStack {
                if let path = network.logoPath, let url = URL(string: "https://image.tmdb.org/t/p/\(APIClient.shared.idealThumbnailSize)\(path)") {
                    CachedImage(url: url, themeColor: baseColor) { _ in } placeholder: {
                        Text(network.name)
                            .font(.system(size: 14, weight: .black))
                            .multilineTextAlignment(.center)
                    }
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 40)
                    .padding(.horizontal, 20)
                    .opacity(isHovered ? 0 : 1)
                    .scaleEffect(isHovered ? 0.9 : 1)
                } else {
                    Text(network.name)
                        .font(.system(size: 16, weight: .black))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .opacity(isHovered ? 0 : 1)
                        .scaleEffect(isHovered ? 0.9 : 1)
                }
                
                if isHovered {
                    VStack(spacing: 4) {
                        Text(network.name)
                            .font(.system(size: 15, weight: .black))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        
                        Text("\(network.count) items")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                    .padding(.horizontal, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .frame(height: 90)
        .padding(10)
        .scaleEffect(isHovered ? 1.04 : (isAppeared ? 1.0 : 0.9))
        .opacity(isAppeared ? 1 : 0)
        .shadow(color: (network.themeColorHex.flatMap { Color(hex: $0) } ?? .black).opacity(isHovered ? 0.3 : 0), radius: isHovered ? 12 : 0, y: isHovered ? 8 : 0)
        .onAppear {
            let delay = Double(staggerIndex ?? 0 % 20) * 0.03
            withAnimation(.smooth(duration: 0.4).delay(delay)) {
                isAppeared = true
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

struct UltraPillTile: View {
    let item: DiscoveryNode
    let icon: String
    let color: Color
    var staggerIndex: Int? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    @State private var isAppeared = false
    
    var body: some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 8,
                bottomTrailingRadius: 24,
                topTrailingRadius: 8,
                style: .continuous
            )
            .fill(.thinMaterial)
            .opacity(colorScheme == .dark ? 0.8 : 0.4)
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 24,
                    bottomLeadingRadius: 8,
                    bottomTrailingRadius: 24,
                    topTrailingRadius: 8,
                    style: .continuous
                )
                .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.05))
            }
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 24,
                    bottomLeadingRadius: 8,
                    bottomTrailingRadius: 24,
                    topTrailingRadius: 8,
                    style: .continuous
                )
                .stroke(color.opacity(isHovered ? 0.5 : 0.2), lineWidth: 1)
            }
            
            VStack(spacing: 4) {
                if !isHovered {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(color)
                        .padding(.bottom, 2)
                        .transition(.opacity)
                }
                
                Text(item.name)
                    .font(.system(size: 14, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                
                if isHovered {
                    Text("\(item.count) items")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .frame(height: 90)
        .padding(10)
        .scaleEffect(isHovered ? 1.04 : (isAppeared ? 1.0 : 0.9))
        .opacity(isAppeared ? 1 : 0)
        .shadow(color: color.opacity(isHovered ? 0.3 : 0), radius: isHovered ? 12 : 0, y: isHovered ? 8 : 0)
        .onAppear {
            let delay = Double(staggerIndex ?? 0 % 20) * 0.03
            withAnimation(.smooth(duration: 0.4).delay(delay)) {
                isAppeared = true
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
