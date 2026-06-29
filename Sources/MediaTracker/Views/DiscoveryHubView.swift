import SwiftUI
import SwiftData

struct DiscoveryHubView: View {
    @Environment(\.modelContext) private var modelContext
    let namespace: Namespace.ID
    @Bindable var viewModel: MediaViewModel
    let onFilterSelected: (DiscoveryFilter) -> Void
    
    @AppStorage("hidden_studios") private var hiddenStudios: String = ""
    @State private var hasDataLoaded = false
    @State private var isFastScrolling = false
    @State private var scrollTask: Task<Void, Never>?
    @State private var networkTab: NetworkTab = .networks
    
    enum NetworkTab { case networks, studios }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 60) {
                if hasDataLoaded {
                    let hasAnyContent = !viewModel.discovery.cachedBadges.isEmpty ||
                        !viewModel.discovery.cachedNetworks.isEmpty ||
                        !viewModel.discovery.cachedStudios.isEmpty ||
                        !viewModel.discovery.cachedGenres.isEmpty ||
                        !viewModel.discovery.cachedLanguages.isEmpty

                    if hasAnyContent {
                        LibrarySummaryBanner(modelContainer: modelContext.container)

                        if !viewModel.discovery.cachedBadges.isEmpty {
                            DiscoverySection(title: "Recent Activity", icon: "sparkles", nodes: viewModel.discovery.cachedBadges, style: .text, isFastScrolling: isFastScrolling, limit: 6) { node in
                                onFilterSelected(DiscoveryFilter(type: .badge, name: node.name))
                            }
                        }

                        if !viewModel.discovery.cachedNetworks.isEmpty || !viewModel.discovery.cachedStudios.isEmpty {
                            let currentNodes = networkTab == .networks ? viewModel.discovery.cachedNetworks : viewModel.discovery.cachedStudios
                            let sectionTitle = networkTab == .networks ? "Networks" : "Studios"
                            DiscoverySection(title: sectionTitle, icon: "tv", nodes: currentNodes, style: .logo, isFastScrolling: isFastScrolling, limit: 12, headerAccessory: {
                                HStack(spacing: 6) {
                                    NetworkTabPill("Networks", isSelected: networkTab == .networks) { networkTab = .networks }
                                    NetworkTabPill("Studios", isSelected: networkTab == .studios) { networkTab = .studios }
                                }
                            }) { node in
                                onFilterSelected(DiscoveryFilter(type: networkTab == .networks ? .network : .studio, name: node.name, sourceNames: node.sourceNames))
                            }
                        }

                        DiscoverySection(title: "Genres", icon: "film", nodes: viewModel.discovery.cachedGenres, style: .text, isFastScrolling: isFastScrolling, limit: 12) { node in
                            onFilterSelected(DiscoveryFilter(type: .genre, name: node.name))
                        }

                        if !viewModel.discovery.cachedLanguages.isEmpty {
                            DiscoverySection(title: "Languages", icon: "globe", nodes: viewModel.discovery.cachedLanguages, style: .text, isFastScrolling: isFastScrolling, limit: 6) { node in
                                onFilterSelected(DiscoveryFilter(type: .language, name: node.id))
                            }
                        }
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "sparkles")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary.opacity(0.3))
                            Text("No discovery data yet")
                                .font(.headline)
                            Text("Add some titles to your library to see discovery insights here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                }
            }
            .padding(.top, 30)
            .padding(.bottom, 20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Discovery Hub")
        .scrollBounceBehavior(.always)
        .scrollIndicators(.hidden)
        .background {
            ScrollVelocityTracker(
                isFastScrolling: $isFastScrolling,
                scrollTask: $scrollTask
            )
        }
        .onAppear { refreshData(force: false) }
        .refreshable { 
            refreshData(force: true) 
        }
        .onChange(of: viewModel.filter.discoveryRefreshTrigger) {
            hasDataLoaded = false
            refreshData(force: false)
        }
        .onChange(of: SleepManager.shared.isAsleep) { _, isAsleep in
            if !isAsleep {
                hasDataLoaded = false
            }
        }
    }
    
    private func refreshData(force: Bool) {
        if !force, hasDataLoaded, let last = viewModel.discovery.lastDiscoveryRefresh, Date().timeIntervalSince(last) < 30 {
            return
        }

        if force {
            Task {
                await MainActor.run { NetworkThemeManager.shared.resetAll() }
            }
        }

        Task {
            if force {
                let oldLogos = viewModel.discovery.cachedNetworks.compactMap(\.logoPath)
                for path in oldLogos {
                    if let url = APIClient.tmdbImageURL(path: path, size: "w300") {
                        await ImageCache.shared.removeImage(forKey: url)
                    }
                }
            }

            let container = modelContext.container
            let localHidden = hiddenStudios
            let syncService = DiscoverySyncService(modelContainer: container)

            let isEmpty = await syncService.isHubDataEmpty()
            if !isEmpty {
                self.hasDataLoaded = true
            }

            if force || isEmpty {
                await syncService.syncLibrary(force: force)
            }

            let hubData = await syncService.fetchHubData(hiddenStudios: localHidden)

            await MainActor.run {
                withAnimation(AppTheme.Animation.springGentle) {
                    self.viewModel.discovery.lastDiscoveryRefresh = Date()
                    self.viewModel.discovery.cachedNetworks = hubData.networks
                    self.viewModel.discovery.cachedStudios = hubData.studios
                    self.viewModel.discovery.cachedGenres = hubData.genres
                    self.viewModel.discovery.cachedLanguages = hubData.languages
                    self.viewModel.discovery.cachedBadges = hubData.badges
                    self.hasDataLoaded = true
                }
            }
            prewarmLogos(networks: hubData.networks + hubData.studios)
        }
    }

    private func prewarmLogos(networks: [DiscoveryNode]) {
        let logoURLs = networks.compactMap { node -> URL? in
            guard let path = node.logoPath else { return nil }
            return APIClient.tmdbImageURL(path: path, size: "w300").flatMap { URL(string: $0) }
        }
        if !logoURLs.isEmpty {
            Task {
                ImageCache.shared.prewarmImages(urls: logoURLs, targetSize: CGSize(width: 100, height: 50))
            }
        }
    }
}

// MARK: - Network Tab Pill

private struct NetworkTabPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.Font.caption)
                .kerning(0.5)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.10) : Color.clear)
                )
                .overlay(
                    Capsule()
                        .stroke(.quaternary, lineWidth: isSelected ? 0 : 0.5)
                )
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Discovery Hub") {
    @Previewable @State var viewModel = MediaViewModel()
    @Previewable var namespace = Namespace().wrappedValue
    
    DiscoveryHubView(
        namespace: namespace,
        viewModel: viewModel,
        onFilterSelected: { _ in }
    )
    .modelContainer(try! ModelContainer(
        for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self,
             NetworkEntity.self, GenreEntity.self, LanguageEntity.self, ProviderEntity.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    ))
}
