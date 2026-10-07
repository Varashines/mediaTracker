import SwiftData
import SwiftUI

struct MainLibraryView: View {
    let items: [MediaThumbnailMetadata]
    var isLoading: Bool = false
    let featuredCarouselItems: [MediaThumbnailMetadata]
    let recentlyAdded: [MediaThumbnailMetadata]
    let homeContinueWatching: [MediaThumbnailMetadata]
    let groupedItems: [(String, [MediaThumbnailMetadata])]
    let recommendations: [MediaThumbnailMetadata]
    let pickOfTheDay: [MediaThumbnailMetadata]
    let selectedCategory: NavigationCategory
    let searchText: String
    let selectedNetworks: [String]?
    let namespace: Namespace.ID
    let onSelectHero: (MediaThumbnailMetadata) -> Void
    let onNetworkSelected: ([String]) -> Void
    let onCategorySelected: (NavigationCategory) -> Void
    let onBack: (() -> Void)?
    let onLoadMore: () -> Void
    let onTrendingAdd: ((MediaSearchResult) -> Void)?
    @Bindable var viewModel: MediaViewModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isFastScrolling) private var isFastScrolling

    var isCategoryPage: Bool {
        return selectedCategory == .movie || selectedCategory == .tvShow
    }

    private var isLibraryCategory: Bool {
        switch selectedCategory {
        case .all, .movie, .tvShow, .completed: return true
        default: return false
        }
    }

    private struct GridFilterKey: Equatable {
        let category: NavigationCategory
        let searchText: String
        let networks: [String]
        let languages: [String]
        let genres: [String]
        let years: [String]
        let states: [MediaState]
        let providers: [String]
        let sortOrder: SortOrder
        let groupBy: GroupBy
        let collectionID: UUID?
    }

    private var gridFilterKey: GridFilterKey {
        GridFilterKey(
            category: selectedCategory,
            searchText: searchText,
            networks: selectedNetworks ?? [],
            languages: viewModel.filter.selectedLanguages,
            genres: viewModel.filter.selectedGenres,
            years: viewModel.filter.selectedYears,
            states: viewModel.filter.selectedStates,
            providers: viewModel.filter.selectedProviders,
            sortOrder: viewModel.filter.currentSortOrder,
            groupBy: viewModel.filter.currentGroupBy,
            collectionID: viewModel.collection.selectedCollectionID
        )
    }

    private var activeFilterEntries: [(id: String, label: String)] {
        var entries: [(id: String, label: String)] = []
        if !viewModel.filter.selectedNetworks.isEmpty {
            entries.append(("networks", "Networks · \(viewModel.filter.selectedNetworks.count)"))
        }
        if !viewModel.filter.selectedLanguages.isEmpty {
            entries.append(("languages", "Languages · \(viewModel.filter.selectedLanguages.count)"))
        }
        if !viewModel.filter.selectedGenres.isEmpty {
            entries.append(("genres", "Genres · \(viewModel.filter.selectedGenres.count)"))
        }
        if !viewModel.filter.selectedYears.isEmpty {
            entries.append(("years", "Years · \(viewModel.filter.selectedYears.count)"))
        }
        if !viewModel.filter.selectedStates.isEmpty {
            entries.append(("states", "Statuses · \(viewModel.filter.selectedStates.count)"))
        }
        if !viewModel.filter.selectedProviders.isEmpty {
            entries.append(("providers", "Providers · \(viewModel.filter.selectedProviders.count)"))
        }
        return entries
    }

    private func clearFilterSection(_ id: String) {
        switch id {
        case "networks": viewModel.filter.selectedNetworks = []
        case "languages": viewModel.filter.selectedLanguages = []
        case "genres": viewModel.filter.selectedGenres = []
        case "years": viewModel.filter.selectedYears = []
        case "states": viewModel.filter.selectedStates = []
        case "providers": viewModel.filter.selectedProviders = []
        default: break
        }
        viewModel.filterSubject.send()
    }

    var body: some View {
        let columns: [GridItem] = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]

        VStack(spacing: 0) {
            if isLibraryCategory, !activeFilterEntries.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.tiny) {
                        ForEach(activeFilterEntries, id: \.id) { entry in
                            HStack(spacing: 4) {
                                Text(entry.label)
                                    .font(AppTheme.Font.caption.weight(.medium))
                                    .lineLimit(1)

                                Button {
                                    withAnimation(AppTheme.Animation.springSnappy) {
                                        clearFilterSection(entry.id)
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Circle())
                                .help("Remove \(entry.label)")
                            }
                            .padding(.leading, AppTheme.Spacing.compact)
                            .padding(.trailing, 6)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(AppTheme.Colors.accent.opacity(colorScheme == .dark ? 0.15 : 0.10))
                            )
                            .overlay {
                                Capsule()
                                    .stroke(AppTheme.Colors.accent.opacity(0.25), lineWidth: 0.8)
                            }
                        }

                        Button {
                            withAnimation(AppTheme.Animation.springSnappy) {
                                viewModel.filter.resetFilters()
                                viewModel.filterSubject.send()
                            }
                        } label: {
                            Text("Clear all")
                                .font(AppTheme.Font.caption.weight(.bold))
                                .foregroundStyle(AppTheme.Colors.accent)
                                .padding(.horizontal, AppTheme.Spacing.compact)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(AppTheme.Colors.surfaceSubtle(for: colorScheme)))
                                .overlay {
                                    Capsule().stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 0.8)
                                }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Capsule())
                        .help("Clear all active filters")
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .padding(.vertical, AppTheme.Spacing.tiny)
                }
            }

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                    if selectedCategory == .home && searchText.isEmpty && (selectedNetworks?.isEmpty ?? true) {
                        HomeViewSections(
                            homeContinueWatching: homeContinueWatching,
                            featuredCarouselItems: featuredCarouselItems,
                            groupedItems: groupedItems,
                            recentlyAdded: recentlyAdded,
                            recommendations: recommendations,
                            recommendationsLoaded: viewModel.display.recommendationsFetched,
                            pickOfTheDay: pickOfTheDay,
                            trendingMovies: viewModel.trendingMovies,
                            trendingShows: viewModel.trendingShows,
                            namespace: namespace,
                            onSelectHero: onSelectHero,
                            onCategorySelected: onCategorySelected,
                            onTrendingAdd: onTrendingAdd,
                            onFetchRecommendations: {
                                let actor = MediaFilterActor.shared(modelContainer: modelContext.container)
                                viewModel.fetchRecommendationsIfNeeded(actor: actor)
                            },
                            onFetchPickOfTheDay: {
                                let actor = MediaFilterActor.shared(modelContainer: modelContext.container)
                                viewModel.fetchPickOfTheDayIfNeeded(actor: actor)
                            },
                            onFetchTrending: {
                                viewModel.fetchTrendingIfNeeded()
                            }
                        )
                        .transition(.opacity)
                    }

                    if selectedCategory != .home {
                        LibraryGridSection(
                            items: items,
                            isLoading: isLoading,
                            groupedItems: groupedItems,
                            recentlyAdded: recentlyAdded,
                            featuredCarouselItems: featuredCarouselItems,
                            selectedCategory: selectedCategory,
                            searchText: searchText,
                            selectedNetworks: selectedNetworks,
                            namespace: namespace,
                            disableHover: false,
                            columns: columns,
                            viewModel: viewModel,
                            onLoadMore: onLoadMore
                        )
                        .transition(.opacity)
                    }
                }
                .id("library-scroll-top")
            }
            .scrollBounceBehavior(selectedCategory == .home ? .always : .basedOnSize)
            .scrollIndicators(.hidden)
                .trackFastScrollingEnv()
                .onChange(of: gridFilterKey) { _, _ in
                    AppTheme.Animation.with(AppTheme.Animation.gridSettle) {
                        scrollProxy.scrollTo("library-scroll-top", anchor: .top)
                    }
                }
            }
        }
    }
}
