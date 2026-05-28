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
    var viewModel: MediaViewModel
    
    @State private var searchVM: SearchViewModel
    @State private var selectedType: SearchType = .all
    @AppStorage("recent_searches") private var recentSearchesData: String = ""

    private var recentSearches: [String] {
        recentSearchesData.split(separator: "\n").map(String.init)
    }

    private func addRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var recent = recentSearches
        recent.removeAll { $0 == trimmed }
        recent.insert(trimmed, at: 0)
        recentSearchesData = Array(recent.prefix(10)).joined(separator: "\n")
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search movies and shows")
        .background(Color.clear)
        .onChange(of: searchText) { oldValue, newValue in
            searchVM.libraryTMDBIDs = viewModel.libraryTMDBIDs
            searchVM.handleSearchTextChange(newValue, selectedType: selectedType)
        }
        .onChange(of: selectedType) { _, newType in
            searchVM.libraryTMDBIDs = viewModel.libraryTMDBIDs
            if !searchText.isEmpty {
                searchVM.triggerSearch(text: searchText, selectedType: newType)
            }
        }
        .onChange(of: MediaStateService.shared.refreshedItemID) { _, _ in
            searchVM.libraryTMDBIDs = viewModel.libraryTMDBIDs
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
            searchVM.libraryTMDBIDs = viewModel.libraryTMDBIDs
            if !searchText.isEmpty {
                searchVM.triggerSearch(text: searchText, selectedType: selectedType)
            }
        }
        .onDisappear {
            searchVM.cancelAllSearchOperations()
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Media Type")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                
                Picker("", selection: $selectedType) {
                    ForEach(SearchType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 200)
                
                Button {} label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Tip: Use \"y:2023\" to filter results by release year.")
                
                Spacer()
                
                if searchVM.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
            .padding(.vertical, 12)

            Divider().padding(.horizontal, AppTheme.Spacing.pageMargin)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
                recentSearchesSection
                localResultsSection
                webResultsSection
            }
            .padding(.vertical, 30)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var recentSearchesSection: some View {
        let recent = recentSearches
        if searchText.isEmpty && !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent Searches")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .kerning(1.2)
                    Spacer()
                    Button("Clear") {
                        recentSearchesData = ""
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recent, id: \.self) { query in
                            Button {
                                searchText = query
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 10))
                                    Text(query)
                                }
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }
            }
        }
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
                .padding(.horizontal, AppTheme.Spacing.pageMargin)

                let columns = [GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(searchVM.filteredLocalResults) { metadata in
                        MediaThumbnailView(metadata: metadata, mode: .grid, showTypeBadge: true) {
                            isSearchActive = false
                            if let item = modelContext.model(for: metadata.id) as? MediaItem {
                                onSelectLocal?(item)
                            }
                        }
                        .accessibilityAddTraits(.isButton)
                        .id("local_\(metadata.id)")
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
                HStack {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                    Text("Global Search")
                        .font(.title3.bold())
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)

                let columns = [GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(combined) { result in
                        MediaThumbnailView(result: result, isLocal: false) {
                            searchVM.addMedia(result, modelContext: modelContext) { item in
                                isSearchActive = false
                                onSelectLocal?(item)
                            }
                        }
                        .accessibilityAddTraits(.isButton)
                        .id("web_\(result.id)")
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
