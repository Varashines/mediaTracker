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
    private func getFilterActor() -> MediaFilterActor {
        MediaFilterActor.shared(modelContainer: modelContext.container)
    }

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)]
    private let pageSize = 50

    private var canShowRecommendations: Bool {
        MooreMetricsService.shared.isConfigured &&
        (filter.type == .studio || filter.type == .genre) &&
        !likedTitles.isEmpty
    }

    private var likedTitles: [String] {
        var titles: [String] = []
        for item in items {
            if item.tasteValue == "Love" || item.tasteValue == "Like" {
                titles.append(item.title)
            }
        }
        return titles
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
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
                                        isFastScrolling: isFastScrolling)
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
                .scrollBounceBehavior(.basedOnSize)
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
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppTheme.Colors.accent)
                    .clipShape(Capsule())
                    .shadow(color: AppTheme.Colors.accent.opacity(0.3), radius: 8, y: 4)
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

        switch filter.type {
        case .studio: network = filter.sourceNames ?? [filter.name]
        case .genre: genre = filter.name
        case .language: language = filter.name
        case .badge:
            badge = filter.name
            sortOrder = .recentInteraction
        }

        Task {
            do {
                let result = try await filterActor.filterAndSort(
                    category: .all, searchText: "", sortOrder: sortOrder,
                    network: network, language: language, genre: genre, badge: badge,
                    limit: pageSize, offset: offset
                )
                if Task.isCancelled { return }
                await MainActor.run {
                    items.append(contentsOf: result.displayed)
                    isLoadingMore = false
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
        let titles = likedTitles
        let domain = recommendedDomain
        let cacheKey = "\(filter.type.rawValue)_\(filter.name)_\(titles.sorted().joined(separator: "|"))"

        // Check 30-day persisted cache
        if let cached = loadCachedRecommendations(key: cacheKey) {
            recommendations = cached
            showRecommendations = true
            return
        }

        isLoadingRecommendations = true

        recsTask = Task {
            async let asyncLabels = MooreMetricsService.shared.fetchCharacteristics(for: domain)
            var mutableResults = await MooreMetricsService.shared.recommend(domain: domain, items: titles, limit: 10, labels: await asyncLabels)
            guard !mutableResults.isEmpty else {
                await MainActor.run {
                    AppErrorState.shared.showToast("No recommendations found", style: .info)
                    isLoadingRecommendations = false
                }
                return
            }
            guard !Task.isCancelled else { return }

            if mutableResults.count >= 3 {
                let topProfile = MooreMetricsService.shared.buildPreferenceProfile(
                    from: mutableResults.map { ($0.characteristics, $0.score) }
                )
                if !topProfile.isEmpty {
                    let debugMode = UserDefaults.standard.bool(forKey: UserDefaultsKeys.mmDebugMode.rawValue)
                    if debugMode {
                        await MainActor.run { debugSelectedTraits = Array(topProfile.keys) }
                    }

                    guard !Task.isCancelled else { return }

                    let prefResults = await MooreMetricsService.shared.recommendByPreferences(
                        domain: domain, preferences: topProfile, limit: 5, labels: await asyncLabels
                    )
                    var seen = Set(mutableResults.map(\.name))
                    for rec in prefResults where !seen.contains(rec.name) {
                        mutableResults.append(rec)
                        seen.insert(rec.name)
                    }
                }
            }

            let inputCount = max(titles.count, 1)
            let finalResults = Array(mutableResults.prefix(10)).map { rec in
                MooreMetricsRecommendation(
                    id: rec.id,
                    name: rec.name,
                    score: inputCount > 1 ? rec.score / log2(Double(inputCount) + 1) : rec.score,
                    characteristics: rec.characteristics,
                    reason: rec.reason
                )
            }

            // Persist to 30-day cache
            saveCachedRecommendations(key: cacheKey, recommendations: finalResults)

            await MainActor.run {
                recommendations = finalResults
                isLoadingRecommendations = false
                showRecommendations = true
            }
        }
    }

    private func saveCachedRecommendations(key: String, recommendations: [MooreMetricsRecommendation]) {
        let prefix = "mm_rec_cache_"
        if let data = try? JSONEncoder().encode(recommendations) {
            UserDefaults.standard.set(data, forKey: prefix + key)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: prefix + key + "_ts")
        }
    }

    private func loadCachedRecommendations(key: String) -> [MooreMetricsRecommendation]? {
        let prefix = "mm_rec_cache_"
        let thirtyDays: TimeInterval = 30 * 24 * 3600

        guard let data = UserDefaults.standard.data(forKey: prefix + key),
              let cached = try? JSONDecoder().decode([MooreMetricsRecommendation].self, from: data),
              !cached.isEmpty,
              let timestamp = UserDefaults.standard.object(forKey: prefix + key + "_ts") as? TimeInterval,
              Date().timeIntervalSince1970 - timestamp < thirtyDays else {
            return nil
        }
        return cached
    }

    private var recommendedDomain: String {
        // Check if all items are movies or TV shows
        let hasMovies = items.contains { $0.type == .movie }
        let hasTV = items.contains { $0.type == .tvShow }

        if hasMovies && !hasTV { return "moviedive" }
        if hasTV && !hasMovies { return "showdive" }
        // Mixed or unknown — default to showdive
        return "showdive"
    }

    private func fetchItems() {
        fetchTask?.cancel()
        fetchTask = Task {
            let filterActor = getFilterActor()
            var network: [String]? = nil
            var language: String? = nil
            var genre: String? = nil
            var badge: String? = nil
            var sortOrder: SortOrder = .alphabetical
            
            switch filter.type {
            case .studio: network = filter.sourceNames ?? [filter.name]
            case .genre: genre = filter.name
            case .language: language = filter.name
            case .badge: 
                badge = filter.name
                sortOrder = .recentInteraction
            }
            
            do {
                let result = try await filterActor.filterAndSort(
                    category: .all, searchText: "", sortOrder: sortOrder,
                    network: network, language: language, genre: genre, badge: badge,
                    limit: pageSize, offset: 0
                )
                if Task.isCancelled { return }
                await MainActor.run {
                    withAnimation {
                        self.items = result.displayed
                        self.totalCount = result.totalCount
                        self.isLoading = false
                    }
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
        
        switch filter.type {
        case .studio: network = filter.sourceNames ?? [filter.name]
        case .genre: genre = filter.name
        case .language: language = filter.name
        case .badge: badge = filter.name
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
                    badge: badge
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
