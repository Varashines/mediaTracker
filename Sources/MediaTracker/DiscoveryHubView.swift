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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Discovery Hub")
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

        viewModel.isBatchRefreshing = true
        let container = modelContext.container
        let localHidden = hiddenStudios
        let syncService = DiscoverySyncService(modelContainer: container)

        Task {
            // Pre-check for existing data to avoid flicker
            let isEmpty = await syncService.isHubDataEmpty()
            if !isEmpty {
                self.hasDataLoaded = true
            }

            // 1. Local Aggregation - ONLY if forced or empty
            if force || isEmpty {
                await syncService.syncLibrary(force: force)
            }

            // 2. Fetch all components thread-safely via actor
            let hubData = await syncService.fetchHubData(hiddenStudios: localHidden)

            withAnimation(AppTheme.Animation.springGentle) {
                self.viewModel.lastDiscoveryRefresh = Date()
                self.viewModel.cachedNetworks = hubData.networks
                self.viewModel.cachedGenres = hubData.genres
                self.viewModel.cachedLanguages = hubData.languages
                self.viewModel.cachedBadges = hubData.badges
                self.hasDataLoaded = true
                self.viewModel.isBatchRefreshing = false
            }
        }
    }
}
