import SwiftUI
import SwiftData

struct MainLibraryView: View {
    let items: [MediaThumbnailMetadata]
    let featuredCarouselItems: [MediaThumbnailMetadata]
    let recentlyAdded: [MediaThumbnailMetadata]
    let homeContinueWatching: [MediaThumbnailMetadata]
    let groupedItems: [(String, [MediaThumbnailMetadata])]
    let recommendations: [MediaThumbnailMetadata]
    let selectedCategory: String?
    let showingUpcomingOnly: Bool
    let searchText: String
    let selectedNetworks: [String]?
    let namespace: Namespace.ID
    @Binding var isFastScrolling: Bool
    let onSelectHero: (MediaThumbnailMetadata) -> Void
    let onNetworkSelected: ([String]) -> Void
    let onLoadMore: () -> Void
    var viewModel: MediaViewModel

    @Environment(\.modelContext) private var modelContext
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    @State private var visibleCount = 40
    @State private var scrollTimer: Timer?
    
    @State private var upcomingScrollProgress: Double = 0
    @State private var upcomingScrollSpace = UUID().uuidString
    @State private var upcomingContentWidth: CGFloat = 0
    @State private var upcomingContainerWidth: CGFloat = 0

    @State private var continueWatchingScrollProgress: Double = 0
    @State private var continueWatchingScrollSpace = UUID().uuidString
    @State private var continueWatchingContentWidth: CGFloat = 0
    @State private var continueWatchingContainerWidth: CGFloat = 0

    @State private var forYouScrollProgress: Double = 0
    @State private var forYouScrollSpace = UUID().uuidString
    @State private var forYouContentWidth: CGFloat = 0
    @State private var forYouContainerWidth: CGFloat = 0

    var isCategoryPage: Bool {
        guard let cat = selectedCategory else { return false }
        return MediaType(rawValue: cat) != nil
    }

    var isMainSection: Bool {
        ["Home", "InProgress", "Watchlist", "All", "Archive", "Loved", "Completed", "Disliked", "Binge", "Upcoming"].contains(selectedCategory)
    }

    var body: some View {
        GeometryReader { mainGeo in
            let availableWidth = mainGeo.size.width
            let itemWidth: CGFloat = 160
            let spacing: CGFloat = 20
            let horizontalPadding: CGFloat = 30
            let usableWidth = availableWidth - (horizontalPadding * 2)
            let columnsCount = max(2, Int(usableWidth / (itemWidth + spacing)))
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnsCount)

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    if selectedCategory == "Home" && searchText.isEmpty && selectedNetworks == nil {
                        // Continue Watching (Top Carousel)
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(
                                title: "Continue Watching", 
                                icon: "play.fill", 
                                iconColor: .blue,
                                scrollProgress: homeContinueWatching.count > 1 ? continueWatchingScrollProgress : nil
                            )
                            
                            if !homeContinueWatching.isEmpty {
                                ScrollViewReader { proxy in
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 20) {
                                            Spacer(minLength: 10)
                                            ForEach(homeContinueWatching) { metadata in
                                                if let item = modelContext.model(for: metadata.id) as? MediaItem, !item.isDeleted {
                                                    Button {
                                                        onSelectHero(metadata)
                                                    } label: {
                                                        MediaThumbnailView(metadata: metadata, mode: .hero, namespace: namespace, isFastScrolling: isFastScrolling)
                                                    }
                                                    .buttonStyle(.interactive)
                                                }
                                            }
                                            Spacer(minLength: 10)
                                        }
                                        .padding(.vertical, 15)
                                        .background(
                                            GeometryReader { geo in
                                                let minX = geo.frame(in: .named(continueWatchingScrollSpace)).minX
                                                Color.clear
                                                    .preference(key: ScrollOffsetKey.self, value: [continueWatchingScrollSpace: minX])
                                                    .onAppear { continueWatchingContentWidth = geo.size.width }
                                                    .onChange(of: geo.size.width) { _, newValue in continueWatchingContentWidth = newValue }
                                            }
                                        )
                                    }
                                    .coordinateSpace(name: continueWatchingScrollSpace)
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear
                                                .onAppear { continueWatchingContainerWidth = geo.size.width }
                                                .onChange(of: geo.size.width) { _, newValue in continueWatchingContainerWidth = newValue }
                                        }
                                    )
                                    .onPreferenceChange(ScrollOffsetKey.self) { dict in
                                        guard let minX = dict[continueWatchingScrollSpace] else { return }
                                        let maxScroll = max(1, continueWatchingContentWidth - continueWatchingContainerWidth)
                                        let currentScroll = max(0, -minX)
                                        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                                            continueWatchingScrollProgress = min(1.0, currentScroll / maxScroll)
                                        }
                                    }
                                    .scrollClipDisabled()
                                }
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 20) {
                                        ForEach(0..<6, id: \.self) { _ in
                                            MediaThumbnailPlaceholder(mode: .hero)
                                        }
                                    }
                                    .padding(.horizontal, 30)
                                    .padding(.vertical, 15)
                                }
                                .scrollClipDisabled()
                            }
                        }
                        .padding(.bottom, 20)

                        // Personalized For You (Middle Carousel)
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(
                                title: "For You", 
                                icon: "sparkles", 
                                iconColor: .yellow,
                                scrollProgress: recommendations.count > 1 ? forYouScrollProgress : nil
                            )
                            
                            if !recommendations.isEmpty {
                                ScrollViewReader { proxy in
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 24) {
                                            Spacer(minLength: 16)
                                            ForEach(recommendations) { metadata in
                                                if let item = modelContext.model(for: metadata.id) as? MediaItem, !item.isDeleted {
                                                    Button {
                                                        onSelectHero(metadata)
                                                    } label: {
                                                        HomeHeroCard(metadata: metadata, item: item, namespace: namespace, isFastScrolling: isFastScrolling)
                                                    }
                                                    .buttonStyle(.interactive)
                                                }
                                            }
                                            Spacer(minLength: 16)
                                        }
                                        .padding(.vertical, 20)
                                        .background(
                                            GeometryReader { geo in
                                                let minX = geo.frame(in: .named(forYouScrollSpace)).minX
                                                Color.clear
                                                    .preference(key: ScrollOffsetKey.self, value: [forYouScrollSpace: minX])
                                                    .onAppear { forYouContentWidth = geo.size.width }
                                                    .onChange(of: geo.size.width) { _, newValue in forYouContentWidth = newValue }
                                            }
                                        )
                                    }
                                    .coordinateSpace(name: forYouScrollSpace)
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear
                                                .onAppear { forYouContainerWidth = geo.size.width }
                                                .onChange(of: geo.size.width) { _, newValue in forYouContainerWidth = newValue }
                                        }
                                    )
                                    .onPreferenceChange(ScrollOffsetKey.self) { dict in
                                        guard let minX = dict[forYouScrollSpace] else { return }
                                        let maxScroll = max(1, forYouContentWidth - forYouContainerWidth)
                                        let currentScroll = max(0, -minX)
                                        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                                            forYouScrollProgress = min(1.0, currentScroll / maxScroll)
                                        }
                                    }
                                    .scrollClipDisabled()
                                }
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 24) {
                                        ForEach(0..<3, id: \.self) { _ in
                                            HomeHeroCardPlaceholder()
                                        }
                                    }
                                    .padding(.horizontal, 30)
                                    .padding(.vertical, 20)
                                }
                                .scrollClipDisabled()
                            }
                        }
                        .padding(.bottom, 20)
                    }

                    // 2. Eager Featured Carousel (Upcoming View)
                    if showingUpcomingOnly && searchText.isEmpty && selectedNetworks == nil && !featuredCarouselItems.isEmpty {
                        VStack(alignment: .leading, spacing: 15) {
                            SectionHeader(
                                title: "Featured",
                                icon: nil,
                                iconColor: .primary,
                                scrollProgress: featuredCarouselItems.count > 1 ? upcomingScrollProgress : nil
                            )
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 20) {
                                    ForEach(featuredCarouselItems) { metadata in
                                        if let item = modelContext.model(for: metadata.id) as? MediaItem, !item.isDeleted {
                                            Button {
                                                onSelectHero(metadata)
                                            } label: {
                                                MediaThumbnailView(metadata: metadata, mode: .hero, isUpcomingSection: true, namespace: namespace, isFastScrolling: isFastScrolling)
                                                    .id(metadata.versionHash)
                                            }
                                            .buttonStyle(.interactive)
                                        }
                                    }
                                }
                                .padding(.horizontal, 30)
                                .padding(.vertical, 20)
                                .background(
                                    GeometryReader { geo in
                                        let minX = geo.frame(in: .named(upcomingScrollSpace)).minX
                                        Color.clear
                                            .preference(key: ScrollOffsetKey.self, value: [upcomingScrollSpace: minX])
                                            .onAppear { upcomingContentWidth = geo.size.width }
                                            .onChange(of: geo.size.width) { _, newValue in upcomingContentWidth = newValue }
                                    }
                                )
                            }
                            .coordinateSpace(name: upcomingScrollSpace)
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear { upcomingContainerWidth = geo.size.width }
                                        .onChange(of: geo.size.width) { _, newValue in upcomingContainerWidth = newValue }
                                }
                            )
                            .onPreferenceChange(ScrollOffsetKey.self) { dict in
                                guard let minX = dict[upcomingScrollSpace] else { return }
                                let maxScroll = max(1, upcomingContentWidth - upcomingContainerWidth)
                                let currentScroll = max(0, -minX)
                                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                                    upcomingScrollProgress = min(1.0, currentScroll / maxScroll)
                                }
                            }
                        }
                        .compositingGroup()
                    }
                    
                    VStack(alignment: .leading, spacing: 15) {
                        // Header Logic
                        if let networks = selectedNetworks, let first = networks.first {
                            let title = networks.count == 1 ? first : "Merged Studios"
                            SectionHeader(title: title, icon: "tv", iconColor: appAccent.color)
                                .overlay(alignment: .trailing) {
                                    Button { withAnimation { onNetworkSelected([]) } } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.trailing, 40)
                                }
                        }
 else if !isCategoryPage && !isMainSection && selectedCategory != "Discover" {
                            SectionHeader(title: selectedCategory ?? "Library", icon: "folder", iconColor: .secondary)
                        } else if selectedCategory == "Upcoming" {
                            SectionHeader(title: "Queue", icon: "list.bullet.indent", iconColor: .secondary)
                                .padding(.bottom, 10)
                        }
                        
                        if items.isEmpty && groupedItems.isEmpty {
                            if viewModel.isInitialLoading {
                                // Section-Aware Grid Skeletons
                                VStack(alignment: .leading, spacing: 25) {
                                    if selectedCategory == "Home" {
                                        SectionHeader(title: "Coming Soon", icon: "calendar", iconColor: .secondary)
                                    } else {
                                        SectionHeader(title: "Loading Library...", icon: "hourglass", iconColor: .secondary)
                                    }
                                    
                                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                        ForEach(0..<12, id: \.self) { _ in
                                            MediaThumbnailPlaceholder(mode: .grid)
                                        }
                                    }
                                    .padding(.horizontal, 30)
                                }
                                .padding(.top, 10)
                            } else {
                                LibraryEmptyStateView(category: selectedCategory) {
                                    withAnimation {
                                        viewModel.selectedCategory = "Discover"
                                    }
                                }
                            }
                        } else {
                            // 2. Eager Recently Added Row (Always Ready)
                            if selectedCategory == "All" && searchText.isEmpty && selectedNetworks == nil {
                                VStack(alignment: .leading, spacing: 15) {
                                    SectionHeader(title: "Recently Added", icon: "clock.badge.checkmark", iconColor: .orange)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 20) {
                                            ForEach(recentlyAdded) { metadata in
                                                if let item = modelContext.model(for: metadata.id) as? MediaItem, !item.isDeleted {
                                                    NavigationLink(value: item) {
                                                        MediaThumbnailView(metadata: metadata, mode: .grid, isFastScrolling: isFastScrolling).id(metadata.versionHash)
                                                    }
                                                    .buttonStyle(.interactive)
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 30)
                                        .padding(.vertical, 15)
                                    }
                                    .scrollClipDisabled()
                                }
                                .compositingGroup()
                                Divider().padding(.horizontal, 30).padding(.bottom, 20)
                            }

                            // 3. Main Collection with Chunking & Pagination
                            if viewModel.currentGroupBy == .none && selectedCategory != "Archive" && selectedCategory != "Home" && selectedCategory != "Binge" {
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                    let baseItems = showingUpcomingOnly ? Array(items.dropFirst(featuredCarouselItems.count)) : items
                                    
                                    ForEach(baseItems.indices, id: \.self) { idx in
                                        let metadata = baseItems[idx]
                                        if let item = modelContext.model(for: metadata.id) as? MediaItem, !item.isDeleted {
                                            NavigationLink(value: item) {
                                                MediaThumbnailView(metadata: metadata, mode: .grid, showTypeBadge: !isCategoryPage, isUpcomingSection: showingUpcomingOnly, namespace: namespace, staggerIndex: idx, isFastScrolling: isFastScrolling)
                                                    .id(metadata.versionHash)
                                                    .entranceStagger(index: idx)
                                                    .onAppear {
                                                        let lastID = items.last?.id
                                                        if metadata.id == lastID {
                                                            onLoadMore()
                                                        }
                                                    }
                                            }
                                            .buttonStyle(.interactive)
                                            .draggable(item.id)
                                        }
                                    }
                                }
                                .padding(.horizontal, 30)
                                .padding(.top, 20)
                                .padding(.bottom, 40)
                            } else {
                                // Grouped View
                                VStack(alignment: .leading, spacing: 60) {
                                    ForEach(groupedItems, id: \.0) { (key, groupMetadatas) in
                                        VStack(alignment: .leading, spacing: 25) {
                                            SectionHeader(
                                                title: key,
                                                icon: (key == "Coming Soon" && selectedCategory == "Home") ? "calendar" : nil,
                                                iconColor: .secondary
                                            )
                                            
                                            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                                ForEach(groupMetadatas) { metadata in
                                                    if let item = modelContext.model(for: metadata.id) as? MediaItem, !item.isDeleted {
                                                        NavigationLink(value: item) {
                                                            MediaThumbnailView(metadata: metadata, mode: .grid, showTypeBadge: viewModel.currentGroupBy != .category, isUpcomingSection: showingUpcomingOnly, namespace: namespace, isFastScrolling: isFastScrolling)
                                                                .id(metadata.versionHash)
                                                                .entranceStagger(index: 0)
                                                        }
                                                        .buttonStyle(.interactive)
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, 30)
                                            .padding(.top, 10)
                                        }
                                    }
                                }
                                .padding(.bottom, 40)
                            }
                        }
                    }
                }
                .padding(.vertical, 20)
                .background {
                    GeometryReader { geo in
                        let currentY = geo.frame(in: .global).minY
                        Color.clear
                            .onChange(of: currentY) { oldValue, newValue in
                                let velocity = abs(newValue - oldValue)
                                if velocity > 30 && !isFastScrolling {
                                    isFastScrolling = true
                                }
                                
                                scrollTimer?.invalidate()
                                scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
                                    Task { @MainActor in
                                        withAnimation(.smooth) {
                                            isFastScrolling = false
                                        }
                                    }
                                }
                            }
                    }
                }
            }
            .scrollClipDisabled()
            .onChange(of: SleepManager.shared.isAsleep) { oldValue, isAsleep in
                if isAsleep {
                    scrollTimer?.invalidate()
                    isFastScrolling = false
                }
            }
            .onAppear { visibleCount = 40 }
            .onChange(of: items.count) { visibleCount = 40 }
        }
    }
}
