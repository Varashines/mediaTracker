import SwiftUI
import SwiftData

struct DiscoveryHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var existingItems: [MediaItem]
    let namespace: Namespace.ID
    @Bindable var viewModel: MediaViewModel
    let onFilterSelected: (DiscoveryFilter) -> Void
    
    @AppStorage("hidden_studios") private var hiddenStudios: String = ""
    @State private var hasDataLoaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 60) { // Increased spacing for scale effect
                if hasDataLoaded {
                    // 1. Recent Activity (Badges)
                    if !viewModel.cachedBadges.isEmpty {
                        DiscoverySection(title: "Recent Activity", icon: "sparkles", nodes: viewModel.cachedBadges, style: .text) { node in
                            onFilterSelected(DiscoveryFilter(type: .badge, name: node.name))
                        }
                    }

                    // 2. Networks & Studios (Full Grid)
                    DiscoverySection(title: "Networks & Studios", icon: "tv", nodes: viewModel.cachedNetworks, style: .logo) { node in
                        onFilterSelected(DiscoveryFilter(type: .studio, name: node.name, sourceNames: node.sourceNames))
                    }

                    // 3. Genres (Full Grid)
                    DiscoverySection(title: "Genres", icon: "film", nodes: viewModel.cachedGenres, style: .text) { node in
                        onFilterSelected(DiscoveryFilter(type: .genre, name: node.name))
                    }

                    // 4. Languages (Full Grid)
                    DiscoverySection(title: "Languages", icon: "globe", nodes: viewModel.cachedLanguages, style: .text) { node in
                        onFilterSelected(DiscoveryFilter(type: .language, name: node.id))
                    }
                } else {
                    // Loading State
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                    .padding(.top, 100)
                }
            }
            .padding(.top, 30)
            .padding(.bottom, 20)
            .padding(.bottom, 100)
            // Essential: Prevent clipping during scaling
            .scrollTargetLayout()
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { refreshData(force: false) }
        .refreshable { 
            refreshData(force: true) 
        }
        .onChange(of: viewModel.discoveryRefreshTrigger) {
            refreshData(force: true)
        }
    }
    
    private func refreshData(force: Bool) {
        if !force, hasDataLoaded, let last = viewModel.lastDiscoveryRefresh, Date().timeIntervalSince(last) < 30 {
            return
        }

        // Phase 5 Optimization: Pre-check for existing data to avoid flicker
        let netDescriptor = FetchDescriptor<NetworkEntity>()
        let existingCount = (try? modelContext.fetchCount(netDescriptor)) ?? 0
        if existingCount > 0 {
            self.hasDataLoaded = true
        }

        viewModel.isBatchRefreshing = true
        let container = modelContext.container
        let localHidden = hiddenStudios

        let syncService = DiscoverySyncService(modelContainer: container)

        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)

            let netDescriptor = FetchDescriptor<NetworkEntity>(sortBy: [
                SortDescriptor(\.count, order: .reverse),
                SortDescriptor(\.name, order: .forward)
            ])
            let genreDescriptor = FetchDescriptor<GenreEntity>(sortBy: [
                SortDescriptor(\.count, order: .reverse),
                SortDescriptor(\.name, order: .forward)
            ])
            let langDescriptor = FetchDescriptor<LanguageEntity>(sortBy: [
                SortDescriptor(\.count, order: .reverse),
                SortDescriptor(\.code, order: .forward)
            ])
            let badgeDescriptor = FetchDescriptor<BadgeEntity>(sortBy: [
                SortDescriptor(\.count, order: .reverse),
                SortDescriptor(\.label, order: .forward)
            ])

            let existingNets = (try? context.fetch(netDescriptor)) ?? []
            let existingGenres = (try? context.fetch(genreDescriptor)) ?? []
            let existingBadges = (try? context.fetch(badgeDescriptor)) ?? []

            // 1. Local Aggregation - ONLY if forced or empty
            if force || (existingNets.isEmpty && existingGenres.isEmpty && existingBadges.isEmpty) {
                await syncService.syncLibrary(force: force)
            }

            let nets = (try? context.fetch(netDescriptor)) ?? []
            let hiddenSet = Set(localHidden.components(separatedBy: ",").filter { !$0.isEmpty })
            let filteredNets = nets.filter { !hiddenSet.contains($0.name) }

            let snNets = filteredNets.map { DiscoveryNode(name: $0.name, logoPath: $0.logoPath, count: $0.count, themeColorHex: $0.themeColorHex, sourceNames: $0.sourceNames) }
            let snGenres = ((try? context.fetch(genreDescriptor)) ?? []).map { DiscoveryNode(name: $0.name, logoPath: nil, count: $0.count) }
            let snLangs = ((try? context.fetch(langDescriptor)) ?? []).map {
                let name = LanguageUtils.languageName(for: $0.code)
                return DiscoveryNode(name: name, code: $0.code, logoPath: nil, count: $0.count)
            }
            let snBadges = ((try? context.fetch(badgeDescriptor)) ?? []).map { DiscoveryNode(name: $0.label, logoPath: nil, count: $0.count) }

            await MainActor.run {
                withAnimation(.smooth(duration: 0.5)) {
                    self.viewModel.lastDiscoveryRefresh = Date()
                    self.viewModel.cachedNetworks = snNets
                    self.viewModel.cachedGenres = snGenres
                    self.viewModel.cachedLanguages = snLangs
                    self.viewModel.cachedBadges = snBadges
                    self.hasDataLoaded = true
                    self.viewModel.isBatchRefreshing = false
                }
            }
        }
    }
}
