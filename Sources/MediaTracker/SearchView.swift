import SwiftData
import SwiftUI

enum SearchType: String, CaseIterable {
    case all = "All"
    case movie = "Movies"
    case tvShow = "TV Shows"
}

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext

    @Binding var searchText: String
    @Binding var isSearchActive: Bool
    var submitTrigger: Int
    var viewModel: MediaViewModel
    @State private var selectedType: SearchType = .all
    @State private var resultsCount = 0

    @State private var movieResults: [MediaSearchResult] = []
    @State private var tvResults: [MediaSearchResult] = []
    @State private var filteredLocalResults: [MediaThumbnailMetadata] = []

    @State private var isSearching = false
    @State private var isOfflineResultsOnly = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var searchTask: Task<Void, Never>?

    private var allWebResults: [MediaSearchResult] {
        let lookup = viewModel.libraryTMDBIDs
        var results: [MediaSearchResult] = []
        
        if selectedType == .all || selectedType == .movie {
            results.append(
                contentsOf: movieResults.filter { !lookup.contains("movie_\($0.id)") }.prefix(15))
        }
        if selectedType == .all || selectedType == .tvShow {
            results.append(
                contentsOf: tvResults.filter { !lookup.contains("tv_\($0.id)") }.prefix(15))
        }
        return results
    }

    init(
        searchText: Binding<String>, isSearchActive: Binding<Bool>, submitTrigger: Int,
        initialType: MediaType? = nil, viewModel: MediaViewModel, onSelectLocal: ((MediaItem) -> Void)? = nil
    ) {
        self._searchText = searchText
        self._isSearchActive = isSearchActive
        self.submitTrigger = submitTrigger
        self.viewModel = viewModel
        self.onSelectLocal = onSelectLocal
        if let type = initialType {
            let searchType: SearchType
            switch type {
            case .movie: searchType = .movie
            case .tvShow: searchType = .tvShow
            }
            _selectedType = State(initialValue: searchType)
        } else {
            _selectedType = State(initialValue: .all)
        }
    }

    var onSelectLocal: ((MediaItem) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            offlineWarningSection
            resultsScrollView
        }
        .background(Color.clear)
        .onChange(of: searchText) { oldValue, newValue in
            handleSearchTextChange(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaItemRefreshed)) { _ in
            searchTask?.cancel()
            searchTask = Task { await performSearch() }
        }
        .alert("Search Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .onAppear {
            if !searchText.isEmpty {
                searchTask = Task { await performSearch() }
            }
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Media Type")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                
                Picker("Media Type", selection: $selectedType) {
                    ForEach(SearchType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 10)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 16)
            .padding(.bottom, 8)

            HStack {
                Text("Tip: Use \"y:2023\" to filter results by release year.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 12)

            Divider().padding(.horizontal, 30)
        }
        .background(.ultraThinMaterial)
        .zIndex(10)
    }

    @ViewBuilder
    private var offlineWarningSection: some View {
        if isOfflineResultsOnly {
            HStack {
                Image(systemName: "wifi.slash")
                Text("Offline: showing library results only")
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.1))
        }
    }

    @ViewBuilder
    private var resultsScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                localResultsSection
                webResultsSection
            }
            .padding(.vertical, 30)
        }
    }

    @ViewBuilder
    private var localResultsSection: some View {
        if !searchText.isEmpty && !filteredLocalResults.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: "tray.full.fill")
                        .foregroundStyle(.secondary)
                    Text("In Your Library")
                        .font(.title3.bold())
                }
                .padding(.horizontal, 30)

                let columns = [GridItem(.adaptive(minimum: 160), spacing: 25, alignment: .top)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                    ForEach(filteredLocalResults) { metadata in
                        MediaThumbnailView(metadata: metadata, mode: .grid, showTypeBadge: true) {
                            isSearchActive = false
                            if let item = modelContext.model(for: metadata.id) as? MediaItem {
                                onSelectLocal?(item)
                            }
                        }
                        .id("local_\(metadata.id)")
                    }
                }
                .padding(.horizontal, 30)
            }
            
            Divider().padding(.horizontal, 30)
        }
    }

    @ViewBuilder
    private var webResultsSection: some View {
        if !allWebResults.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                    Text("Global Search")
                        .font(.title3.bold())
                }
                .padding(.horizontal, 30)

                let columns = [GridItem(.adaptive(minimum: 160), spacing: 25, alignment: .top)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                    ForEach(allWebResults) { result in
                        MediaThumbnailView(result: result, isLocal: false) {
                            addMedia(result)
                        }
                        .id("web_\(result.id)")
                    }
                }
                .padding(.horizontal, 30)
            }
        } else if !isSearching && !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private func handleSearchTextChange(_ newValue: String) {
        searchTask?.cancel()
        if newValue.isEmpty {
            movieResults = []
            tvResults = []
            filteredLocalResults = []
        } else {
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { return }
                await performSearch()
            }
        }
    }

    private func performSearch() async {
        guard !SleepManager.shared.isAsleep else { return }
        
        isSearching = true
        isOfflineResultsOnly = false
        
        let currentSearch = searchText
        let currentSelectedType = selectedType
        let container = modelContext.container

        do {
            // Parallel Search: Local + Web
            async let localSearch: [MediaThumbnailMetadata] = {
                let filterActor = MediaFilterActor(modelContainer: container)
                let category: NavigationCategory
                switch currentSelectedType {
                case .all: category = .all
                case .movie: category = .movie
                case .tvShow: category = .tvShow
                }
                let result = try? await filterActor.filterAndSort(
                    category: category,
                    searchText: currentSearch,
                    sortOrder: .alphabetical,
                    network: nil,
                    language: nil,
                    limit: 50,
                    offset: 0
                )
                return result?.displayed ?? []
            }()

            async let webMovies: [MediaSearchResult] = {
                if currentSelectedType == .all || currentSelectedType == .movie {
                    return (try? await APIClient.shared.searchMovies(query: currentSearch)) ?? []
                }
                return []
            }()

            async let webTV: [MediaSearchResult] = {
                if currentSelectedType == .all || currentSelectedType == .tvShow {
                    return (try? await APIClient.shared.searchTVShows(query: currentSearch)) ?? []
                }
                return []
            }()

            let (local, movies, tv) = await (localSearch, webMovies, webTV)

            if Task.isCancelled { return }

            await MainActor.run {
                self.filteredLocalResults = local
                self.movieResults = movies
                self.tvResults = tv
                self.isSearching = false
                self.isOfflineResultsOnly = false
                withAnimation {
                    self.resultsCount += 1
                }
            }
        }
    }

    @MainActor
    private func addMedia(_ result: MediaSearchResult) {
        FeedbackManager.shared.trigger(.addToLibrary)
        let typePrefix = result.type == .movie ? "movie" : "tv"
        let uniqueID = "\(typePrefix)_\(result.id)"

        // Prevent race condition (double-click)
        if DataService.shared.isProcessing(id: uniqueID) { return }
        DataService.shared.startProcessing(id: uniqueID)

        let container = modelContext.container
        let tmdbID = Int(result.id) ?? 0
        let type = result.type
        let title = result.title
        let overview = result.overview
        let poster = result.posterURL
        let release = result.releaseDate
        
        Task.detached(priority: .userInitiated) {
            defer { Task { @MainActor in DataService.shared.stopProcessing(id: uniqueID) } }

            let service = BackgroundDataService(modelContainer: container)
            let result = await service.createNewMediaItem(
                uniqueID: uniqueID, 
                tmdbID: tmdbID, 
                type: type, 
                title: title, 
                overview: overview, 
                posterURL: poster, 
                releaseDateString: release
            )

            // Sync Discovery Entities
            if let id = result.id {
                let sync = DiscoverySyncService(modelContainer: container)
                let actorContext = ModelContext(container)
                if let fetchedItem = actorContext.model(for: id) as? MediaItem {
                    await sync.updateItemAdded(fetchedItem)
                }
            }

            await MainActor.run {
                if result.isExisting {
                    AppErrorState.shared.showToast("Title already in Library", systemImage: "info.circle.fill", type: .info)
                }
                
                isSearchActive = false
                if let id = result.id, let item = modelContext.model(for: id) as? MediaItem {
                    onSelectLocal?(item)
                }
            }
        }
    }
}
