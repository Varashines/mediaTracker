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

    var body: some View {
        let columns: [GridItem] = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]

        VStack(spacing: 0) {
            if isLibraryCategory, !activeFilterEntries.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.tiny) {
                        Text("Library filters")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        ForEach(activeFilterEntries, id: \.id) { entry in
                            Text(entry.label)
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, AppTheme.Spacing.small)
                                .padding(.vertical, AppTheme.Spacing.micro)
                                .background(
                                    Capsule()
                                        .fill(AppTheme.Colors.surfaceGhost(for: colorScheme))
                                )
                        }
                        Button("Clear all") {
                            viewModel.filter.resetFilters()
                            viewModel.filterSubject.send()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, AppTheme.Spacing.tiny)
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .padding(.vertical, AppTheme.Spacing.tiny)
                }
            }

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
            }
            .scrollBounceBehavior(selectedCategory == .home ? .always : .basedOnSize)
            .scrollIndicators(.hidden)
            .trackFastScrollingEnv()
        }
    }
}
