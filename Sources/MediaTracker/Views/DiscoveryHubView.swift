import SwiftUI
import SwiftData

struct DiscoveryHubView: View {
    @Environment(\.modelContext) private var modelContext
    let namespace: Namespace.ID
    @Bindable var viewModel: MediaViewModel
    let onFilterSelected: (DiscoveryFilter) -> Void
    
    @AppStorage("hidden_studios") private var hiddenStudios: String = ""
    @State private var hasDataLoaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 60) {
                if hasDataLoaded {
                    if !viewModel.cachedBadges.isEmpty {
                        DiscoverySection(title: "Recent Activity", icon: "sparkles", nodes: viewModel.cachedBadges, style: .text) { node in
                            onFilterSelected(DiscoveryFilter(type: .badge, name: node.name))
                        }
                    }

                    DiscoverySection(title: "Networks & Studios", icon: "tv", nodes: viewModel.cachedNetworks, style: .logo) { node in
                        onFilterSelected(DiscoveryFilter(type: .studio, name: node.name, sourceNames: node.sourceNames))
                    }

                    DiscoverySection(title: "Genres", icon: "film", nodes: viewModel.cachedGenres, style: .text) { node in
                        onFilterSelected(DiscoveryFilter(type: .genre, name: node.name))
                    }

                    DiscoverySection(title: "Languages", icon: "globe", nodes: viewModel.cachedLanguages, style: .text) { node in
                        onFilterSelected(DiscoveryFilter(type: .language, name: node.id))
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                }
            }
            .padding(.top, 30)
            .padding(.bottom, 20)
            .padding(.bottom, 100)
            .scrollTargetLayout()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Discovery Hub")
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { refreshData(force: false) }
        .refreshable { 
            refreshData(force: true) 
        }
        .onChange(of: viewModel.discoveryRefreshTrigger) {
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
        if !force, hasDataLoaded, let last = viewModel.lastDiscoveryRefresh, Date().timeIntervalSince(last) < 30 {
            return
        }

        if force {
            Task {
                await MainActor.run { NetworkThemeManager.shared.resetAll() }
            }
        }

        Task {
            if force {
                let oldLogos = viewModel.cachedNetworks.compactMap(\.logoPath)
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
                    self.viewModel.lastDiscoveryRefresh = Date()
                    self.viewModel.cachedNetworks = hubData.networks
                    self.viewModel.cachedGenres = hubData.genres
                    self.viewModel.cachedLanguages = hubData.languages
                    self.viewModel.cachedBadges = hubData.badges
                    self.hasDataLoaded = true
                }
            }
            prewarmLogos(networks: hubData.networks)
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
             NetworkEntity.self, GenreEntity.self, LanguageEntity.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    ))
}
