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
    var viewModel: MediaViewModel // Existing global MediaViewModel
    
    @State private var searchVM: SearchViewModel
    @State private var selectedType: SearchType = .all
    @State private var resultsCount = 0

    private var allWebResults: [MediaSearchResult] {
        let lookup = viewModel.libraryTMDBIDs
        var results: [MediaSearchResult] = []
        
        if selectedType == .all || selectedType == .movie {
            results.append(
                contentsOf: searchVM.movieResults.filter { !lookup.contains("movie_\($0.id)") }.prefix(15))
        }
        if selectedType == .all || selectedType == .tvShow {
            results.append(
                contentsOf: searchVM.tvResults.filter { !lookup.contains("tv_\($0.id)") }.prefix(15))
        }
        return results
    }

    init(
        searchText: Binding<String>, isSearchActive: Binding<Bool>, submitTrigger: Int,
        initialType: MediaType? = nil, viewModel: MediaViewModel, onSelectLocal: ((MediaItem) -> Void)? = nil,
        modelContainer: ModelContainer
    ) {
        self._searchText = searchText
        self._isSearchActive = isSearchActive
        self.submitTrigger = submitTrigger
        self.viewModel = viewModel
        self.onSelectLocal = onSelectLocal
        self._searchVM = State(initialValue: SearchViewModel(modelContainer: modelContainer))
        
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
            searchVM.handleSearchTextChange(newValue, selectedType: selectedType)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaItemRefreshed)) { _ in
            Task { await searchVM.performSearch(text: searchText, selectedType: selectedType) }
        }
        .alert("Search Error", isPresented: $searchVM.showError, presenting: searchVM.errorMessage) { _ in
            Button("OK") { searchVM.errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .onAppear {
            if !searchText.isEmpty {
                Task { await searchVM.performSearch(text: searchText, selectedType: selectedType) }
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
                
                if searchVM.isSearching {
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
        .background {
            if #available(macOS 26.0, *) {
                Rectangle().fill(.clear).glassEffect(.regular)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .zIndex(10)
    }

    @ViewBuilder
    private var offlineWarningSection: some View {
        if searchVM.isOfflineResultsOnly {
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
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var localResultsSection: some View {
        if !searchText.isEmpty && !searchVM.filteredLocalResults.isEmpty {
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
                    ForEach(searchVM.filteredLocalResults) { metadata in
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
                            searchVM.addMedia(result, modelContext: modelContext) { item in
                                isSearchActive = false
                                onSelectLocal?(item)
                            }
                        }
                        .id("web_\(result.id)")
                    }
                }
                .padding(.horizontal, 30)
            }
        } else if !searchVM.isSearching && !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }
    }
}
