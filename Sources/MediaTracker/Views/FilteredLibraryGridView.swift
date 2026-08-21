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
    @Environment(\.sleepManager) private var sleepManager

    @State private var items: [MediaThumbnailMetadata] = []
    @State private var networkColor: Color? = nil
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var totalCount = 0
    @State private var scopedStats: ScopedLibraryStats?
    @State private var showRecommendations = false
    @State private var recommendations: [MooreMetricsRecommendation] = []
    @State private var isLoadingRecommendations = false
    @State private var debugSelectedTraits: [String] = []
    @Environment(\.colorScheme) var colorScheme
    @State private var fetchTask: Task<Void, Never>? = nil
    @State private var updateTask: Task<Void, Never>? = nil
    @State private var loadMoreTask: Task<Void, Never>? = nil
    @State private var scopedStatsTask: Task<Void, Never>? = nil
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

    private var groupedByWeekday: [(Date?, [MediaThumbnailMetadata])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { item in
            item.releaseDate.map(calendar.startOfDay(for:))
        }
        return grouped.sorted { lhs, rhs in
            switch (lhs.key, rhs.key) {
            case let (left?, right?):
                return left < right
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case (nil, nil):
                return false
            }
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(0..<12, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                                .frame(width: 160, height: 240)
                                .shimmering()
                        }
                    }
                    .padding(AppTheme.Spacing.pageMargin)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            } else if items.isEmpty && !isLoading {
                if !searchText.isEmpty {
                    VStack(spacing: AppTheme.Spacing.large) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No results for \"\(searchText)\"")
                            .font(AppTheme.Font.subtitle)
                        Text("Try a different search term or clear the search to see all \(filter.name) titles.")
                            .font(AppTheme.Font.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Clear Search") {
                            searchText = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.Colors.accent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(AppTheme.Spacing.xLarge)
                } else {
                    VStack(spacing: AppTheme.Spacing.large) {
                        Image(systemName: "square.grid.3x3")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No \(filter.name) titles")
                            .font(AppTheme.Font.subtitle)
                        Text("There are no titles matching this \(filter.type.rawValue.lowercased()) in your library yet.")
                            .font(AppTheme.Font.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Browse Discovery") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.Colors.accent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(AppTheme.Spacing.xLarge)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let stats = scopedStats, !items.isEmpty {
                            ScopedInsightsHeader(stats: stats, filterName: filter.name, filterType: filter.type)
                                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        }
                        if filter.type == .onThisWeek {
                            ForEach(Array(groupedByWeekday.enumerated()), id: \.element.0) { groupIdx, group in
                                let day = group.0
                                let dayItems = group.1
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(day?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) ?? "Unknown")
                                        .font(AppTheme.Font.heading)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                        ForEach(Array(dayItems.enumerated()), id: \.element.id) { idx, metadata in
                                            NavigationLink(value: metadata.id) {
                                                MediaThumbnailView(
                                                    metadata: metadata, mode: .grid, namespace: namespace,
                                                    staggerIndex: idx, isFastScrolling: isFastScrolling)
                                                .equatable()
                                            }
                                            .buttonStyle(.interactive)
                                            .onAppear {
                                                let isLastItemInDay = idx == dayItems.count - 1
                                                let isLastGroup = groupIdx == groupedByWeekday.count - 1
                                                if isLastItemInDay && isLastGroup {
                                                    loadMoreItems()
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                                }
                            }
                        } else {
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
                            .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        }
                    }
                    .padding(.top, AppTheme.Spacing.pageMargin)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .trackFastScrolling(isFastScrolling: $isFastScrolling, scrollTask: $scrollTask)
                .background {
                    if let color = networkColor {
                        color.opacity(colorScheme == .dark ? 0.08 : 0.04)
                            .ignoresSafeArea()
                    }
                }
            }
        }
        .navigationTitle(
            sleepManager.isAsleep
                ? ""
                : (filter.type == .language ? LanguageUtils.languageName(for: filter.name) : filter.name)
        )
        .toolbarMaterial(isSleeping: sleepManager.isAsleep)
        .onChange(of: MediaStateService.shared.needsFullRefreshCount) { _, _ in
            ScopedStatsActor.invalidateCache()
            let itemID = MediaStateService.shared.lastChangedItemID
            if let itemID = itemID {
                updateSingleItem(id: itemID)
                fetchScopedStats()
            } else {
                scopedStats = nil
                fetchItems()
                fetchScopedStats()
            }
        }
        .onChange(of: MediaStateService.shared.needsSingleItemUpdateCount) { _, _ in
            guard let itemID = MediaStateService.shared.lastChangedItemID else { return }
            ScopedStatsActor.invalidateCache()
            updateSingleItem(id: itemID)
            fetchScopedStats()
        }
        .task {
            fetchItems()
            if filter.type == .studio {
                fetchNetworkColor()
            }
        }
        .task {
            fetchScopedStats()
        }
        .onDisappear {
            fetchTask?.cancel()
            fetchTask = nil
            updateTask?.cancel()
            updateTask = nil
            loadMoreTask?.cancel()
            loadMoreTask = nil
            scopedStatsTask?.cancel()
            scopedStatsTask = nil
            recsTask?.cancel()
            recsTask = nil
            ImageCache.shared.cancelPrewarming()
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
        .background {
            Button("") { dismiss() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .opacity(0)
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
        case .onThisWeek: sortOrder = .newestRelease
        }

        loadMoreTask?.cancel()
        loadMoreTask = Task {
            do {
                let result = try await filterActor.filterAndSort(
                    category: filter.type == .onThisWeek ? .onThisWeek : .all, searchText: "", sortOrder: sortOrder,
                    network: network, language: language, genre: genre, badge: badge, provider: provider,
                    limit: pageSize, offset: offset
                )
                if Task.isCancelled { return }
                await MainActor.run {
                    items.append(contentsOf: result.displayed)
                    isLoadingMore = false
                    recomputeRecommendationData()
                }

                // Keep the next viewport warm without creating network work for an entire page.
                ImageCache.shared.prewarmImages(
                    result.displayed,
                    limit: 12,
                    targetSize: .thumbSmall,
                    priority: .low
                )
            } catch {
                if !(error is CancellationError) {
                    AppLogger.debug("Error loading more filtered items: \(error)")
                }
                await MainActor.run { isLoadingMore = false }
            }
        }
    }

    private func fetchScopedStats() {
        scopedStatsTask?.cancel()
        scopedStatsTask = Task {
            let actor = ScopedStatsActor(modelContainer: modelContext.container)
            let sections = ScopedStatsSections.visibleSections(for: filter.type)
            let stats = await actor.fetchScopedStats(filter: filter, sections: sections)
            guard !Task.isCancelled, stats.totalItems > 0 else { return }
            await MainActor.run { scopedStats = stats }
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
            case .onThisWeek: sortOrder = .newestRelease
            }

            do {
                let result = try await filterActor.filterAndSort(
                    category: filter.type == .onThisWeek ? .onThisWeek : .all, searchText: "", sortOrder: sortOrder,
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
        case .onThisWeek: break
        }

        updateTask?.cancel()
        updateTask = Task {
            do {
                let filterActor = getFilterActor()
                let updatedMetadata = try await filterActor.fetchMetadataIfMatches(
                    for: id,
                    category: filter.type == .onThisWeek ? .onThisWeek : .all,
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
                            case .onThisWeek:
                                items.sort { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
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
