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
    @State private var refreshTask: Task<Void, Never>?
    @State private var networkTab: NetworkTab = .networks
    
    enum NetworkTab { case networks, studios }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                if hasDataLoaded {
                    let hasAnyContent = !viewModel.discovery.cachedBadges.isEmpty ||
                        !viewModel.discovery.cachedNetworks.isEmpty ||
                        !viewModel.discovery.cachedStudios.isEmpty ||
                        !viewModel.discovery.cachedGenres.isEmpty ||
                        !viewModel.discovery.cachedLanguages.isEmpty ||
                        !viewModel.discovery.cachedProviders.isEmpty

                    if hasAnyContent {
                        if !viewModel.discovery.cachedBadges.isEmpty {
                            DiscoverySection(
                                title: "Recent Activity",
                                icon: "sparkles",
                                nodes: viewModel.discovery.cachedBadges,
                                style: .text,
                                isFastScrolling: isFastScrolling,
                                subtitle: "Your library, lately",
                                isFeatured: true,
                                limit: 6
                            ) { node in
                                onFilterSelected(DiscoveryFilter(type: .badge, name: node.name))
                            }
                        }

                        if !viewModel.discovery.cachedNetworks.isEmpty || !viewModel.discovery.cachedStudios.isEmpty {
                            let currentNodes = networkTab == .networks ? viewModel.discovery.cachedNetworks : viewModel.discovery.cachedStudios
                            let sectionTitle = networkTab == .networks ? "Networks" : "Studios"
                            DiscoverySection(title: sectionTitle, icon: "tv", nodes: currentNodes, style: .logo, isFastScrolling: isFastScrolling, subtitle: "\(currentNodes.count) in your library", limit: 12, headerAccessory: {
                                HStack(spacing: 6) {
                                    NetworkTabPill("Networks", isSelected: networkTab == .networks) { networkTab = .networks }
                                    NetworkTabPill("Studios", isSelected: networkTab == .studios) { networkTab = .studios }
                                }
                            }) { node in
                                onFilterSelected(DiscoveryFilter(type: networkTab == .networks ? .network : .studio, name: node.name, sourceNames: node.sourceNames))
                            }
                        }

                        DiscoverySection(title: "Genres", icon: "film", nodes: viewModel.discovery.cachedGenres, style: .text, isFastScrolling: isFastScrolling, subtitle: "\(viewModel.discovery.cachedGenres.count) represented", limit: 12) { node in
                            onFilterSelected(DiscoveryFilter(type: .genre, name: node.name))
                        }

                        if !viewModel.discovery.cachedLanguages.isEmpty {
                            DiscoverySection(title: "Languages", icon: "globe", nodes: viewModel.discovery.cachedLanguages, style: .text, isFastScrolling: isFastScrolling, subtitle: "\(viewModel.discovery.cachedLanguages.count) represented", limit: 6) { node in
                                onFilterSelected(DiscoveryFilter(type: .language, name: node.id))
                            }
                        }

                        if !viewModel.discovery.cachedProviders.isEmpty {
                            DiscoverySection(title: "Providers", icon: "popcorn.fill", nodes: viewModel.discovery.cachedProviders, style: .logo, isFastScrolling: isFastScrolling, subtitle: "\(viewModel.discovery.cachedProviders.count) available", limit: 6) { node in
                                onFilterSelected(DiscoveryFilter(type: .provider, name: node.name))
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
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                        // Skeleton for sections
                        ForEach(0..<3, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.secondary.opacity(0.08))
                                        .frame(width: 16, height: 16)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.08))
                                        .frame(width: 80, height: 14)
                                }
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: AppTheme.Spacing.medium) {
                                        ForEach(0..<6, id: \.self) { _ in
                                            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                                .fill(Color.secondary.opacity(0.08))
                                                .frame(width: 100, height: 60)
                                                .shimmering()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 30)
                }
            }
            .padding(.top, 30)
            .padding(.bottom, 20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Discovery Hub")
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .trackFastScrolling(isFastScrolling: $isFastScrolling, scrollTask: $scrollTask)
        .onAppear { refreshData(force: false) }
        .refreshable { 
            refreshData(force: true) 
        }
        .onChange(of: viewModel.filter.discoveryRefreshTrigger) {
            hasDataLoaded = false
            refreshData(force: false)
        }
        .onChange(of: MediaStateService.shared.discoveryResyncCount) { _, _ in
            hasDataLoaded = false
            refreshData(force: true)
        }
        .onChange(of: SleepManager.shared.isAsleep) { _, isAsleep in
            if !isAsleep {
                hasDataLoaded = false
                if UserDefaults.standard.bool(forKey: UserDefaultsKeys.discoveryAutoSync.rawValue) {
                    refreshData(force: false)
                }
            }
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
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

        refreshTask?.cancel()
        refreshTask = Task {
            defer { refreshTask = nil }
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

            guard !Task.isCancelled else { return }

            let isEmpty = await syncService.isHubDataEmpty()
            if !isEmpty {
                self.hasDataLoaded = true
            }

            if force || isEmpty {
                await syncService.syncLibrary(force: force)
            }

            guard !Task.isCancelled else { return }

            let hubData = await syncService.fetchHubData(hiddenStudios: localHidden)

            await MainActor.run {
                guard !Task.isCancelled else { return }
                withAnimation(AppTheme.Animation.springGentle) {
                    self.viewModel.discovery.lastDiscoveryRefresh = Date()
                    self.viewModel.discovery.cachedNetworks = hubData.networks
                    self.viewModel.discovery.cachedStudios = hubData.studios
                    self.viewModel.discovery.cachedGenres = hubData.genres
                    self.viewModel.discovery.cachedLanguages = hubData.languages
                    self.viewModel.discovery.cachedBadges = hubData.badges
                    self.viewModel.discovery.cachedProviders = hubData.providers
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
    @State private var isHovered = false
    
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
                        .fill(isHovered && !isSelected ? Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06) : (isSelected ? Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.10) : Color.clear))
                )
                .overlay(
                    Capsule()
                        .stroke(.quaternary, lineWidth: isSelected ? 0 : 0.5)
                )
                .foregroundStyle(isSelected ? .primary : .secondary)
                .scaleEffect(isHovered ? 1.04 : 1.0)
                .animation(AppTheme.Animation.springSnappy, value: isHovered)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
