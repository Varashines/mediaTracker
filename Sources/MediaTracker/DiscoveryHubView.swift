import SwiftUI
import SwiftData

struct DiscoveryHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var existingItems: [MediaItem]
    let namespace: Namespace.ID
    @Bindable var viewModel: MediaViewModel
    let onFilterSelected: (DiscoveryFilter) -> Void
    
    @AppStorage("hidden_studios") private var hiddenStudios: String = ""
    @State private var hasDataLoaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 60) { // Increased spacing for scale effect
                if hasDataLoaded {
                    // 1. Trending Sections
                    VStack(spacing: 40) {
                        trendingSection(title: "Trending Movies", icon: "flame.fill", items: filterExisting(viewModel.trendingMovies))
                        trendingSection(title: "Trending TV Shows", icon: "sparkles", items: filterExisting(viewModel.trendingTV))
                    }
                    .padding(.top, 20)

                    // 2. Networks & Studios (Full Grid)
                    DiscoverySection(title: "Networks & Studios", icon: "tv", nodes: viewModel.cachedNetworks, style: .logo) { node in
                        onFilterSelected(DiscoveryFilter(type: .studio, name: node.name))
                    }

                    // 3. Genres (Full Grid)
                    DiscoverySection(title: "Genres", icon: "film", nodes: viewModel.cachedGenres, style: .text) { node in
                        onFilterSelected(DiscoveryFilter(type: .genre, name: node.name))
                    }

                    // 4. Languages (Full Grid)
                    DiscoverySection(title: "Languages", icon: "globe", nodes: viewModel.cachedLanguages, style: .text) { node in
                        onFilterSelected(DiscoveryFilter(type: .language, name: node.id))
                    }
                } else {
                    // Loading State
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                    .padding(.top, 100)
                }
            }
            .padding(.bottom, 100)
            // Essential: Prevent clipping during scaling
            .scrollTargetLayout()
        }
        .onAppear { refreshData(force: false) }
        .refreshable { refreshData(force: true) }
    }
    
    @ViewBuilder
    private func trendingSection(title: String, icon: String, items: [MediaSearchResult]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeader(title: title, icon: icon, iconColor: .secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(items) { result in
                            MediaThumbnailView(result: result, isLocal: false) {
                                addMedia(result)
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                }
            }
        }
    }

    private func filterExisting(_ results: [MediaSearchResult]) -> [MediaSearchResult] {
        let lookup = Set(existingItems.map { "\($0.id)_\($0.type?.rawValue ?? "")" })
        return results.filter { !lookup.contains("\($0.id)_\($0.type.rawValue)") }
    }

    private func addMedia(_ result: MediaSearchResult) {
        // Implement navigation or addition logic here
        // For simplicity, we can trigger the search item addition logic
        // But better is to just append it to the path if we have it
        // For now, let's keep it consistent with SearchView's addition logic
        // We might need to move addMedia to a shared service if it gets too complex
        
        let typePrefix = result.type == .movie ? "movie" : "tv"
        let uniqueID = "\(typePrefix)_\(result.id)"

        if DataService.shared.isProcessing(id: uniqueID) { return }
        DataService.shared.startProcessing(id: uniqueID)

        Task {
            defer { DataService.shared.stopProcessing(id: uniqueID) }

            let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate<MediaItem> { $0.id == uniqueID })
            if let existing = try? modelContext.fetch(descriptor).first {
                await MainActor.run {
                    viewModel.navigationPath.append(existing)
                }
                return
            }

            let releaseDate = result.releaseDate != nil ? DateUtils.parseDate(result.releaseDate) : nil
            let item = MediaItem(id: uniqueID, title: result.title, overview: result.overview, posterURL: result.posterURL, releaseDate: releaseDate, type: result.type)
            item.dateAdded = Date()
            
            // Basic details fetch (same as SearchView)
            if result.type == .movie, let tmdbID = Int(result.id) {
                if let details = try? await APIClient.shared.fetchMovieDetails(tmdbID: tmdbID) {
                     item.releaseDate = DateUtils.parseDate(details.releaseDate)
                     if let poster = details.posterPath { item.posterURL = "https://image.tmdb.org/t/p/\(APIClient.shared.idealThumbnailSize)\(poster)" }
                     
                     let movieDetails = MovieDetails(tmdbID: tmdbID)
                     movieDetails.item = item
                     movieDetails.runtime = details.runtime
                     movieDetails.genres = details.genres
                     movieDetails.voteAverage = details.voteAverage
                     movieDetails.originalLanguage = details.originalLanguage
                     movieDetails.creators = details.directors.map { $0.name }
                     
                     movieDetails.cast = details.cast.map { c in
                         let profileURL = c.profilePath != nil ? "https://image.tmdb.org/t/p/w185\(c.profilePath!)" : nil
                         let member = CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order)
                         member.movieDetails = movieDetails
                         return member
                     }
                     
                     item.movieDetails = movieDetails
                }
            } else if result.type == .tvShow, let tmdbID = Int(result.id) {
                if let details = try? await APIClient.shared.fetchTVDetails(tmdbID: tmdbID) {
                    if let poster = details.posterPath { item.posterURL = "https://image.tmdb.org/t/p/\(APIClient.shared.idealThumbnailSize)\(poster)" }
                    let tvDetails = TVShowDetails(tmdbID: tmdbID)
                    tvDetails.item = item
                    tvDetails.status = details.status
                    tvDetails.network = details.network
                    tvDetails.numberOfSeasons = details.seasonsCount
                    tvDetails.numberOfEpisodes = details.episodesCount
                    tvDetails.genres = details.genres
                    tvDetails.creators = details.creators.map { $0.name }
                    
                    tvDetails.cast = details.cast.map { c in
                        let profileURL = c.profilePath != nil ? "https://image.tmdb.org/t/p/w185\(c.profilePath!)" : nil
                        let member = CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order)
                        member.tvShowDetails = tvDetails
                        return member
                    }
                    
                    item.tvShowDetails = tvDetails
                }
            }

            modelContext.insert(item)
            try? modelContext.save()
            
            await MainActor.run {
                viewModel.navigationPath.append(item)
            }
        }
    }

    private func refreshData(force: Bool) {
        if !force, hasDataLoaded, let last = viewModel.lastDiscoveryRefresh, Date().timeIntervalSince(last) < 600 {
            return
        }
        
        let container = modelContext.container
        let localHidden = hiddenStudios
        
        let syncService = DiscoverySyncService(modelContainer: container)

        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            // 1. Trending Fetch
            async let trendingMovies = APIClient.shared.fetchTrendingMovies()
            async let trendingTV = APIClient.shared.fetchTrendingTVShows()
            
            // 2. Local Aggregation
            await syncService.syncLibrary(force: force)
            
            let netDescriptor = FetchDescriptor<NetworkEntity>(sortBy: [SortDescriptor(\.count, order: .reverse)])
            let genreDescriptor = FetchDescriptor<GenreEntity>(sortBy: [SortDescriptor(\.count, order: .reverse)])
            let langDescriptor = FetchDescriptor<LanguageEntity>(sortBy: [SortDescriptor(\.count, order: .reverse)])
            
            let nets = (try? context.fetch(netDescriptor)) ?? []
            let hiddenSet = Set(localHidden.components(separatedBy: ",").filter { !$0.isEmpty })
            let filteredNets = nets.filter { !hiddenSet.contains($0.name) }
            
            let snNets = filteredNets.map { DiscoveryNode(name: $0.name, logoPath: $0.logoPath, count: $0.count, themeColorHex: $0.themeColorHex) }
            let snGenres = ((try? context.fetch(genreDescriptor)) ?? []).map { DiscoveryNode(name: $0.name, logoPath: nil, count: $0.count) }
            let snLangs = ((try? context.fetch(langDescriptor)) ?? []).map { 
                let name = LanguageUtils.languageName(for: $0.code)
                return DiscoveryNode(name: name, code: $0.code, logoPath: nil, count: $0.count) 
            }
            
            let fetchedMovies = (try? await trendingMovies) ?? []
            let fetchedTV = (try? await trendingTV) ?? []
            
            await MainActor.run {
                withAnimation(.smooth(duration: 0.5)) {
                    self.viewModel.lastDiscoveryRefresh = Date()
                    self.viewModel.trendingMovies = fetchedMovies
                    self.viewModel.trendingTV = fetchedTV
                    self.viewModel.cachedNetworks = snNets
                    self.viewModel.cachedGenres = snGenres
                    self.viewModel.cachedLanguages = snLangs
                    self.hasDataLoaded = true
                }
            }
        }
    }
}

// MARK: - Rich Grid Components

enum DiscoveryCardStyle {
    case logo, text
}

struct DiscoverySection: View {
    let title: String
    let icon: String
    let nodes: [DiscoveryNode]
    let style: DiscoveryCardStyle
    let onSelected: (DiscoveryNode) -> Void
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: title, icon: icon, iconColor: appAccent.color)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: style == .logo ? 200 : 180), spacing: 24)], spacing: 24) {
                ForEach(nodes) { node in
                    DiscoveryCard(node: node, style: style) { onSelected(node) }
                }
            }
            .padding(.horizontal, 40)
        }
    }
}

struct DiscoveryCard: View {
    let node: DiscoveryNode
    let style: DiscoveryCardStyle
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var isAppeared = false
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic

    private var themeColor: Color {
        if let hex = node.themeColorHex, let color = Color(hex: hex) {
            return color
        }
        return appAccent.color
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Main Layer
                Group {
                    if style == .logo {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.secondary.opacity(colorScheme == .dark ? 0.15 : 0.08))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(themeColor.opacity(isHovered ? 0.6 : 0.15), lineWidth: isHovered ? 2 : 1)
                            }
                    } else {
                        Capsule()
                            .fill(Color.secondary.opacity(colorScheme == .dark ? 0.15 : 0.08))
                            .overlay {
                                Capsule()
                                    .stroke(themeColor.opacity(isHovered ? 0.6 : 0.15), lineWidth: isHovered ? 2 : 1)
                            }
                    }
                }
                .shadow(color: themeColor.opacity(isHovered ? 0.2 : 0), radius: isHovered ? 15 : 0, y: isHovered ? 8 : 0)
                
                if style == .logo {
                    logoContent
                } else {
                    textContent
                }
            }
            .frame(height: style == .logo ? 140 : 80)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .opacity(isAppeared ? 1 : 0)
        .onAppear {
            let delay = Double.random(in: 0...0.15)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay)) {
                isAppeared = true
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isHovered)
        .onHover { isHovered = $0 }
    }
    
    @ViewBuilder
    private var logoContent: some View {
        ZStack {
            if let logo = node.logoPath {
                AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w300\(logo)")) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView().controlSize(.small)
                }
                .frame(width: isHovered ? 90 : 120, height: isHovered ? 45 : 60)
                .offset(y: isHovered ? -15 : 0)
            } else {
                Text(node.name)
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)
                    .offset(y: isHovered ? -15 : 0)
            }
            
            VStack(spacing: 2) {
                if node.logoPath != nil {
                    Text(node.name)
                        .font(.system(size: 14, weight: .semibold))
                        .multilineTextAlignment(.center)
                }
                Text("\(node.count) TITLES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .opacity(isHovered ? 1 : 0)
            .offset(y: isHovered ? 30 : 45)
            .scaleEffect(isHovered ? 1.0 : 0.9)
        }
        .padding(20)
    }
    
    @ViewBuilder
    private var textContent: some View {
        ZStack {
            Text(node.name)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .offset(y: isHovered ? -8 : 0)
            
            Text("\(node.count) ITEMS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .opacity(isHovered ? 1 : 0)
                .offset(y: isHovered ? 12 : 20)
        }
    }
}
