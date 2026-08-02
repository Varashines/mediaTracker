import SwiftData
import SwiftUI

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme

    @Binding var searchText: String
    @Binding var isSearchActive: Bool
    var viewModel: MediaViewModel

    @State private var searchVM: SearchViewModel
    @AppStorage("recent_searches") private var recentSearchesData: String = ""

    private var selectedType: SearchType {
        get { viewModel.filter.searchTypeFilter }
        nonmutating set { viewModel.filter.searchTypeFilter = newValue }
    }

    private var recentSearches: [String] {
        recentSearchesData.split(separator: "\n").map(String.init)
    }

    private func addRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        var recent = recentSearches
        recent.removeAll { $0.lowercased() == trimmed.lowercased() }
        recent.insert(trimmed, at: 0)
        recentSearchesData = Array(recent.prefix(5)).joined(separator: "\n")
    }

    private var popularSearches: [String] {
        var titles: [String] = []
        for movie in viewModel.trendingMovies.prefix(4) {
            titles.append(movie.title)
        }
        for show in viewModel.trendingShows.prefix(4) {
            titles.append(show.title)
        }
        var unique: [String] = []
        for t in titles {
            let trimmed = t.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !unique.contains(where: { $0.lowercased() == trimmed.lowercased() }) {
                unique.append(trimmed)
            }
        }
        if unique.isEmpty {
            return ["Breaking Bad", "Oppenheimer", "Succession", "Severance", "Chernobyl", "Dune"]
        }
        return Array(unique.prefix(6))
    }

    init(
        searchText: Binding<String>, isSearchActive: Binding<Bool>,
        initialType: MediaType? = nil, viewModel: MediaViewModel, onSelectLocal: ((MediaItem) -> Void)? = nil,
        modelContainer: ModelContainer
    ) {
        self._searchText = searchText
        self._isSearchActive = isSearchActive
        self.viewModel = viewModel
        self.onSelectLocal = onSelectLocal
        self._searchVM = State(initialValue: SearchViewModel(modelContainer: modelContainer))

        if let type = initialType {
            let searchType: SearchType
            switch type {
            case .movie: searchType = .movie
            case .tvShow: searchType = .tvShow
            }
            viewModel.filter.searchTypeFilter = searchType
        }
    }

    var onSelectLocal: ((MediaItem) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            offlineWarningSection
            resultsScrollView
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search movies and shows")
        .searchSuggestions {
            if searchText.isEmpty {
                ForEach(recentSearches.prefix(10), id: \.self) { query in
                    Text(query)
                        .searchCompletion(query)
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchVM.displayCache = viewModel.display
            searchVM.handleSearchTextChange(newValue, selectedType: selectedType)
        }
        .onChange(of: selectedType) { _, newType in
            searchVM.displayCache = viewModel.display
            searchVM.clearWebResults()
            if !searchText.isEmpty {
                searchVM.triggerSearch(text: searchText, selectedType: newType)
            }
        }
        .onChange(of: MediaStateService.shared.refreshedItemID) { _, _ in
            searchVM.displayCache = viewModel.display
            if !searchText.isEmpty {
                searchVM.triggerSearch(text: searchText, selectedType: selectedType)
            }
        }
        .onSubmit(of: .search) { addRecentSearch(searchText) }
        .alert("Search Error", isPresented: $searchVM.showError, presenting: searchVM.errorMessage) { _ in
            Button("OK") { searchVM.errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .onAppear {
            searchVM.displayCache = viewModel.display
            viewModel.fetchTrendingIfNeeded()
            if !searchText.isEmpty && searchVM.filteredLocalResults.isEmpty && searchVM.allWebResults.isEmpty {
                searchVM.triggerSearch(text: searchText, selectedType: selectedType)
            }
        }
        .onDisappear {
            searchVM.cancelSearchTaskOnly()
        }
        .background {
            if isSearchActive {
                Group {
                    Button("") { viewModel.filter.searchTypeFilter = .all }
                        .keyboardShortcut("1", modifiers: [.command, .option])
                    Button("") { viewModel.filter.searchTypeFilter = .movie }
                        .keyboardShortcut("2", modifiers: [.command, .option])
                    Button("") { viewModel.filter.searchTypeFilter = .tvShow }
                        .keyboardShortcut("3", modifiers: [.command, .option])
                }
                .opacity(0)
            }
        }
    }

    private let suggestedSearches = ["Breaking Bad", "Oppenheimer", "Succession", "Severance", "Chernobyl", "Dune"]

    @ViewBuilder
    private var filterBar: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()

                HStack(spacing: 4) {
                    filterPill(title: "All", icon: nil, type: .all, shortcut: "⌘⌥1")
                    filterPill(title: "Movies", icon: "film.fill", type: .movie, shortcut: "⌘⌥2")
                    filterPill(title: "TV Shows", icon: "tv.fill", type: .tvShow, shortcut: "⌘⌥3")
                }
                .padding(4)
                .background(
                    Capsule()
                        .fill(AppTheme.Colors.cardFill(for: colorScheme))
                )
                .overlay(
                    Capsule()
                        .stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 0.5)
                )

                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
            .padding(.vertical, 12)

            Divider().padding(.horizontal, AppTheme.Spacing.pageMargin)
        }
    }

    private func filterPill(title: String, icon: String?, type: SearchType, shortcut: String) -> some View {
        let isSelected = selectedType == type
        return Button {
            withAnimation(AppTheme.Animation.springSnappy) {
                viewModel.filter.searchTypeFilter = type
            }
        } label: {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }

                Text(title)
                    .font(isSelected ? AppTheme.Font.bodyBold : AppTheme.Font.body)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text(shortcut)
                    .font(AppTheme.Font.small)
                    .foregroundStyle(isSelected ? AppTheme.Colors.accent : Color.secondary.opacity(0.6))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(isSelected ? AppTheme.Colors.accent.opacity(0.15) : Color.primary.opacity(0.04))
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? AppTheme.Colors.accent.opacity(0.2) : Color.clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var offlineWarningSection: some View {
        if searchVM.isOfflineResultsOnly {
            HStack {
                Image(systemName: "wifi.slash")
                Text("Offline: showing library results only")
            }
            .font(AppTheme.Font.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.1))
        }
    }

    @ViewBuilder
    private var resultsScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.pageMargin) {
                if searchText.isEmpty {
                    recentSearchesLandingSection
                } else if searchVM.isSearching && searchVM.filteredLocalResults.isEmpty && searchVM.allWebResults.isEmpty {
                    VStack(spacing: AppTheme.Spacing.medium) {
                        ForEach(0..<5, id: \.self) { _ in
                            HStack(spacing: AppTheme.Spacing.medium) {
                                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                    .fill(Color.secondary.opacity(0.08))
                                    .frame(width: 50, height: 75)
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.08))
                                        .frame(height: 14)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.06))
                                        .frame(width: 120, height: 10)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, AppTheme.Spacing.pageMargin)
                            .shimmering()
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.compact)
                } else {
                    localResultsSection
                    webResultsSection
                }
            }
            .padding(.vertical, AppTheme.Spacing.xLarge)
            .id(selectedType)
            .transition(.mediaRowArrival)
            .animation(AppTheme.Animation.easeInOut, value: selectedType)
        }
        .scrollBounceBehavior(.always)
        .scrollIndicators(.hidden)
    }

    private func removeRecentSearch(_ query: String) {
        var recent = recentSearches
        recent.removeAll { $0 == query }
        recentSearchesData = recent.joined(separator: "\n")
    }

    @ViewBuilder
    private var recentSearchesLandingSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            if !recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("Recent Searches", systemImage: "clock.arrow.circlepath")
                            .font(AppTheme.Font.heading)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button {
                            recentSearchesData = ""
                        } label: {
                            Text("Clear History")
                                .font(AppTheme.Font.caption)
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(recentSearches, id: \.self) { query in
                            HStack(spacing: 6) {
                                Button {
                                    withAnimation(AppTheme.Animation.springSnappy) {
                                        searchText = query
                                        addRecentSearch(query)
                                    }
                                } label: {
                                    Text(query)
                                        .font(AppTheme.Font.body)
                                        .foregroundStyle(.primary)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    withAnimation(AppTheme.Animation.springSnappy) {
                                        removeRecentSearch(query)
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(AppTheme.Radius.medium)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                Label(recentSearches.isEmpty ? "Popular Searches" : "Suggested Searches", systemImage: "sparkles")
                    .font(AppTheme.Font.heading)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                FlowLayout(spacing: 8) {
                    ForEach(popularSearches, id: \.self) { query in
                        Button {
                            withAnimation(AppTheme.Animation.springSnappy) {
                                searchText = query
                                addRecentSearch(query)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppTheme.Colors.accent)
                                Text(query)
                                    .font(AppTheme.Font.body)
                                    .foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppTheme.Colors.cardFill(for: colorScheme))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                                    .stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 0.5)
                            )
                            .cornerRadius(AppTheme.Radius.medium)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
            }
        }
    }

    @ViewBuilder
    private var localResultsSection: some View {
        if !searchText.isEmpty && !searchVM.filteredLocalResults.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    Image(systemName: "tray.full.fill")
                        .foregroundStyle(.secondary)
                    Text("In Your Library")
                        .font(AppTheme.Font.title3)
                    
                    Text("\(searchVM.filteredLocalResults.count)")
                        .font(AppTheme.Font.caption2)
                        .contentTransition(.numericText())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)

                let columns = [GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(Array(searchVM.filteredLocalResults.enumerated()), id: \.element.id) { idx, metadata in
                        MediaThumbnailView(metadata: metadata, mode: .grid, showTypeBadge: true) {
                            addRecentSearch(searchText)
                            if let item = modelContext.model(for: metadata.id) as? MediaItem {
                                onSelectLocal?(item)
                            }
                        }
                        .accessibilityAddTraits(.isButton)
                        .modifier(StaggerModifier(index: idx, modulo: 6, delayPerStep: 0.04, verticalOffset: 6))
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
            }
            
            Divider().padding(.horizontal, AppTheme.Spacing.pageMargin)
        }
    }

    @ViewBuilder
    private var webResultsSection: some View {
        let combined = searchVM.allWebResults
        if !combined.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                    Text("Global Search")
                        .font(AppTheme.Font.title3)
                    
                    Text("\(combined.count)")
                        .font(AppTheme.Font.caption2)
                        .contentTransition(.numericText())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)

                let columns = [GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(Array(combined.enumerated()), id: \.element.id) { idx, result in
                        MediaThumbnailView(result: result, isLocal: false) {
                            addRecentSearch(searchText)
                            searchVM.addMedia(result, modelContext: modelContext) { item in
                                onSelectLocal?(item)
                            }
                        }
                        .accessibilityAddTraits(.isButton)
                        .modifier(StaggerModifier(index: idx, modulo: 6, delayPerStep: 0.04, verticalOffset: 6))
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
            }
        } else if !searchVM.isSearching && !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }
    }
}

#Preview("Search View") {
    @Previewable @State var searchText = ""
    @Previewable @State var isSearchActive = true
    @Previewable @State var viewModel = MediaViewModel()
    let container = try! ModelContainer(
        for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    
    SearchView(
        searchText: $searchText,
        isSearchActive: $isSearchActive,
        viewModel: viewModel,
        modelContainer: container
    )
}
