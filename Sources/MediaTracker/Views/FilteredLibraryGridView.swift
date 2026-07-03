import SwiftUI
import SwiftData

struct FilteredLibraryGridView: View {
    let filter: DiscoveryFilter
    let namespace: Namespace.ID
    @Binding var isFastScrolling: Bool
    @Binding var isSearchActive: Bool
    @Binding var searchText: String
    var onNavigateToSearch: ((String) -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var items: [MediaThumbnailMetadata] = []
    @State private var networkColor: Color? = nil
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var totalCount = 0
    @State private var showRecommendations = false
    @State private var recommendations: [MooreMetricsRecommendation] = []
    @State private var isLoadingRecommendations = false
    @State private var debugSelectedTraits: [String] = []
    @Environment(\.colorScheme) var colorScheme
    @State private var fetchTask: Task<Void, Never>? = nil
    @State private var updateTask: Task<Void, Never>? = nil
    @State private var recsTask: Task<Void, Never>? = nil
    @State private var scrollTask: Task<Void, Never>? = nil
    @State private var cachedLikedTitles: [String] = []
    @State private var cachedRecommendedDomain: String = "showdive"
    private func getFilterActor() -> MediaFilterActor {
        MediaFilterActor.shared(modelContainer: modelContext.container)
    }

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)]
    private let pageSize = 50

    private var canShowRecommendations: Bool {
        MooreMetricsService.shared.isConfigured &&
        (filter.type == .studio || filter.type == .genre) &&
        !cachedLikedTitles.isEmpty
    }

    var body: some View {
        Group {
            if isLoading {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(0..<12, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                                .frame(width: 160, height: 240)
                                .shimmering()
                        }
                    }
                    .padding(AppTheme.Spacing.pageMargin)
                }
                .scrollBounceBehavior(.always)
                .scrollIndicators(.hidden)
            } else if items.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No items found",
                    systemImage: "square.grid.3x3",
                    description: Text("Try a different filter or add new titles to your library.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { idx, metadata in
                                NavigationLink(value: metadata.id) {
                                    MediaThumbnailView(
                                        metadata: metadata, mode: .grid, namespace: namespace,
                                        staggerIndex: idx, isFastScrolling: isFastScrolling)
                                    .equatable()
                                }
                                .buttonStyle(.interactive)
                                .onAppear {
                                    if idx == items.count - 1 {
                                        loadMoreItems()
                                    }
                                }
                            }
                            if isLoadingMore {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                            }
                        }
                    }
                    .padding(AppTheme.Spacing.pageMargin)
                }
                .scrollBounceBehavior(.always)
                .scrollIndicators(.hidden)
                .background {
                    ScrollVelocityTracker(isFastScrolling: $isFastScrolling, scrollTask: $scrollTask)
                }
                .background {
                    if let color = networkColor {
                        color.opacity(colorScheme == .dark ? 0.08 : 0.04)
                            .ignoresSafeArea()
                    }
                }
            }
        }
        .navigationTitle(filter.type == .language ? LanguageUtils.languageName(for: filter.name) : filter.name)
        .onChange(of: MediaStateService.shared.needsFullRefreshCount) { _, _ in
            let itemID = MediaStateService.shared.lastChangedItemID
            if let itemID = itemID {
                updateSingleItem(id: itemID)
            } else {
                fetchItems()
            }
        }
        .task {
            fetchItems()
            if filter.type == .studio {
                fetchNetworkColor()
            }
        }
        .onDisappear {
            fetchTask?.cancel()
            fetchTask = nil
            updateTask?.cancel()
            updateTask = nil
            recsTask?.cancel()
            recsTask = nil
        }
        .task {
            recomputeRecommendationData()
        }
        .overlay(alignment: .bottomTrailing) {
            if canShowRecommendations && !isLoading {
                Button {
                    fetchRecommendations()
                } label: {
                    HStack(spacing: 6) {
                        if isLoadingRecommendations {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text("Discover More")
                            .font(AppTheme.Font.bodyBold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.secondary)
                    .clipShape(Capsule())
                    .shadow(color: .secondary.opacity(0.3), radius: 8, y: 4)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isLoadingRecommendations)
                .padding(AppTheme.Spacing.pageMargin)
            }
        }
        .sheet(isPresented: $showRecommendations) {
            RecommendationSheet(
                filterName: filter.name,
                filterType: filter.type,
                recommendations: recommendations,
                onDismiss: { showRecommendations = false },
                onSearch: { name in
                    showRecommendations = false
                    onNavigateToSearch?(name)
                },
                debugTraits: debugSelectedTraits
            )
        }
    }

    private func loadMoreItems() {
        guard !isLoadingMore && items.count < totalCount else { return }
        isLoadingMore = true
        let offset = items.count
        let filterActor = getFilterActor()
        var network: [String]? = nil
        var language: String? = nil
        var genre: String? = nil
        var badge: String? = nil
        var sortOrder: SortOrder = .alphabetical

        var provider: String? = nil
        
        switch filter.type {
        case .studio, .network: network = filter.sourceNames ?? [filter.name]
        case .genre: genre = filter.name
        case .language: language = filter.name
        case .badge:
            badge = filter.name
            sortOrder = .recentInteraction
        case .provider: provider = filter.name
        }

        Task {
            do {
                let result = try await filterActor.filterAndSort(
                    category: .all, searchText: "", sortOrder: sortOrder,
                    network: network, language: language, genre: genre, badge: badge, provider: provider,
                    limit: pageSize, offset: offset
                )
                if Task.isCancelled { return }
                await MainActor.run {
                    items.append(contentsOf: result.displayed)
                    isLoadingMore = false
                    recomputeRecommendationData()
                }

                // Prefetch images for newly loaded items so they're ready when the user scrolls to them
                let posterURLs = result.displayed.compactMap { $0.posterURL }.compactMap { URL(string: $0) }
                if !posterURLs.isEmpty {
                    ImageCache.shared.prewarmImages(urls: posterURLs, targetSize: .thumbSmall)
                }
            } catch {
                if !(error is CancellationError) {
                    AppLogger.debug("Error loading more filtered items: \(error)")
                }
                await MainActor.run { isLoadingMore = false }
            }
        }
    }

    private func fetchNetworkColor() {
        let name = filter.name
        let descriptor = FetchDescriptor<NetworkEntity>(predicate: #Predicate { $0.name == name })
        if let network = try? modelContext.fetch(descriptor).first, let hex = network.themeColorHex {
            self.networkColor = Color(hex: hex)
        }
    }

    private func fetchRecommendations() {
        recsTask?.cancel()
        let titles = cachedLikedTitles
        let domain = cachedRecommendedDomain
        let cacheKey = "\(filter.type.rawValue)_\(filter.name)_\(titles.sorted().joined(separator: "|"))"

        isLoadingRecommendations = true

        recsTask = Task {
            let inputCount = max(titles.count, 1)
            let results = await RecommendationService.fetchRecommendations(
                titles: titles,
                domain: domain,
                cachePrefix: "mm_rec_cache_",
                cacheKey: cacheKey
            ) { rec in
                MooreMetricsRecommendation(
                    id: rec.id,
                    name: rec.name,
                    score: inputCount > 1 ? rec.score / log2(Double(inputCount) + 1) : rec.score,
                    characteristics: rec.characteristics,
                    reason: rec.reason
                )
            }

            if results.isEmpty {
                AppErrorState.shared.showToast("No recommendations found", style: .info)
            }

            await MainActor.run {
                recommendations = results
                isLoadingRecommendations = false
                showRecommendations = true
            }
        }
    }

    private func recomputeRecommendationData() {
        cachedLikedTitles = items.filter { $0.tasteValue == "Love" || $0.tasteValue == "Like" }.map(\.title)
        let hasMovies = items.contains { $0.type == .movie }
        let hasTV = items.contains { $0.type == .tvShow }
        cachedRecommendedDomain = hasMovies && !hasTV ? "moviedive" : "showdive"
    }

    private func fetchItems() {
        fetchTask?.cancel()
        fetchTask = Task {
            let filterActor = getFilterActor()
            var network: [String]? = nil
            var language: String? = nil
            var genre: String? = nil
            var badge: String? = nil
            var provider: String? = nil
            var sortOrder: SortOrder = .alphabetical
            
            switch filter.type {
            case .studio, .network: network = filter.sourceNames ?? [filter.name]
            case .genre: genre = filter.name
            case .language: language = filter.name
            case .badge: 
                badge = filter.name
                sortOrder = .recentInteraction
            case .provider: provider = filter.name
            }
            
            do {
                let result = try await filterActor.filterAndSort(
                    category: .all, searchText: "", sortOrder: sortOrder,
                    network: network, language: language, genre: genre, badge: badge, provider: provider,
                    limit: pageSize, offset: 0
                )
                if Task.isCancelled { return }
                await MainActor.run {
                    self.items = result.displayed
                    self.totalCount = result.totalCount
                    self.isLoading = false
                }
            } catch {
                if !(error is CancellationError) {
                    AppLogger.debug("Error fetching filtered items: \(error)")
                }
            }
        }
    }

    private func updateSingleItem(id: PersistentIdentifier) {
        var network: [String]? = nil
        var language: String? = nil
        var genre: String? = nil
        var badge: String? = nil
        var provider: String? = nil
        
        switch filter.type {
        case .studio, .network: network = filter.sourceNames ?? [filter.name]
        case .genre: genre = filter.name
        case .language: language = filter.name
        case .badge: badge = filter.name
        case .provider: provider = filter.name
        }
        
        updateTask?.cancel()
        updateTask = Task {
            do {
                let filterActor = getFilterActor()
                let updatedMetadata = try await filterActor.fetchMetadataIfMatches(
                    for: id,
                    category: .all,
                    searchText: "",
                    network: network,
                    language: language,
                    genre: genre,
                    badge: badge,
                    provider: provider
                )
                if Task.isCancelled { return }
                
                await MainActor.run {
                    withAnimation(AppTheme.Animation.easeInOut) {
                        if let index = items.firstIndex(where: { $0.id == id }) {
                            if let updated = updatedMetadata {
                                items[index] = updated
                            } else {
                                items.remove(at: index)
                            }
                        } else if let updated = updatedMetadata {
                            items.append(updated)
                            
                            // Re-sort the items list
                            switch filter.type {
                            case .badge:
                                items.sort { ($0.lastInteractionDate ?? Date.distantPast) > ($1.lastInteractionDate ?? Date.distantPast) }
                            default:
                                items.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
                            }
                        }
                    }
                }
            } catch {
                if !(error is CancellationError) {
                    AppLogger.debug("Error updating single item in FilteredLibraryGridView: \(error)")
                }
            }
        }
    }
}
