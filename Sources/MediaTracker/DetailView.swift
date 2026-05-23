import SwiftData
import SwiftUI

struct DetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: DetailViewModel
    @State private var isAppeared = false
    @State private var isDeleted = false
    @State private var isCastExpanded = false
    @State private var showHeavyContent = false
    @State private var showingCollectionPicker = false

    var onSearchActor: ((String) -> Void)? = nil
    var namespace: Namespace.ID? = nil

    init(item: MediaItem, namespace: Namespace.ID? = nil, onSearchActor: ((String) -> Void)? = nil)
    {
        _viewModel = State(initialValue: DetailViewModel(item: item))
        self.onSearchActor = onSearchActor
        self.namespace = namespace
    }

    var body: some View {
        ZStack {
            if isDeleted || viewModel.item.modelContext == nil {
                Color(NSColor.windowBackgroundColor).ignoresSafeArea()
            } else {
                contentOverlay
            }
        }
    }

    @ViewBuilder
    private var contentOverlay: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()
            
            // Dynamic Backdrop Blend - optimized with RadialGradient (No heavy dynamic blur)
            GeometryReader { geo in
                RadialGradient(
                    colors: [effectiveThemeColor.opacity(colorScheme == .dark ? 0.22 : 0.08), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: min(geo.size.width, geo.size.height) * 0.95
                )
                .ignoresSafeArea()
            }
            .animation(AppTheme.Animation.springGentle, value: effectiveThemeColor)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                    headerSection
                    tmdbWarningSection
                    castAndTrackingSection
                }
                .padding(.horizontal, AppTheme.Spacing.xLarge)
                .padding(.vertical, AppTheme.Spacing.section)
                .padding(.bottom, 90) // Ensure scroll content doesn't get covered by floating bar
            }
            .scrollBounceBehavior(.basedOnSize)
            
            // Floating Action Bar overlay at bottom
            VStack {
                Spacer()
                DetailFloatingActionBar(
                    viewModel: viewModel,
                    onAddToCollection: { showingCollectionPicker = true },
                    onRefresh: { viewModel.refreshData(force: true) },
                    onDelete: deleteItem
                )
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Details")
        .toolbar { detailToolbar }
        .onAppear {
            viewModel.refreshData()
            withAnimation(AppTheme.Animation.springGentle.delay(0.1)) {
                isAppeared = true
            }
            
            Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                withAnimation(.easeInOut(duration: 0.3)) {
                    showHeavyContent = true
                }
            }
        }
        .onDisappear { isAppeared = false }
        .sheet(isPresented: $showingCollectionPicker) {
            CollectionPickerView(item: viewModel.item)
        }
        .onChange(of: MediaStateService.shared.refreshedItemID) { _, newID in
            if let id = newID, id == viewModel.item.id {
                viewModel.refreshLocalItem()
            }
        }
        .tint(effectiveThemeColor)
    }

    private var effectiveThemeColor: Color {
        viewModel.themeColor
    }

    @ViewBuilder
    private var headerSection: some View {
        MediaHeaderView(
            item: viewModel.item,
            themeColor: effectiveThemeColor,
            viewModel: viewModel,
            namespace: namespace,
            onStatusChange: { newState in
                if newState == .completed {
                    viewModel.markAllAsWatched()
                } else {
                    if let context = viewModel.item.modelContext {
                        SaveCoordinator.shared.requestSave(context)
                    }
                    MediaStateService.shared.postMediaStateChanged(itemID: viewModel.item.persistentModelID)
                }
            }
        )
    }

    @ViewBuilder
    private var tmdbWarningSection: some View {
        let hasNoGenres = viewModel.item.type == .movie && viewModel.item.cachedGenres.isEmpty
        let hasNoNetwork = viewModel.item.type == .tvShow && viewModel.item.cachedNetwork == nil
        
        if hasNoGenres || hasNoNetwork {
            if !APIClient.shared.isTMDBConfigured {
                Text("Please add your TMDB API Key in Settings to see more details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var castAndTrackingSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            if showHeavyContent {
                // 1. TV TRACKING (Modular Card)
                if viewModel.item.type == .tvShow, let tv = viewModel.item.tvShowDetails {
                    ModularSection(title: "Seasons & Episodes", icon: "square.stack.3d.down.right.fill", color: effectiveThemeColor) {
                        TVTrackingView(
                            tvDetails: tv,
                            themeColor: effectiveThemeColor,
                            isRefreshing: viewModel.isRefreshing,
                            onWatchedToggle: { viewModel.checkOverallCompletion() },
                            onSeasonSelected: { season in viewModel.fetchEpisodes(for: season) }
                        )
                        .padding(.top, 4)
                    }
                }

                // 2. TOP CAST (Modular Card)
                if !viewModel.item.displayCast.isEmpty {
                    ModularSection(title: "Top Cast", icon: "person.2.fill", color: effectiveThemeColor) {
                        CastSectionView(
                            cast: viewModel.item.displayCast,
                            themeColor: effectiveThemeColor
                        ) { actorName in
                            onSearchActor?(actorName)
                        }
                    }
                }
            } else {
                // SKELETON LOADER
                VStack(spacing: AppTheme.Spacing.large) {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                        .fill(Color.primary.opacity(0.04))
                        .frame(height: 180)
                    RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                        .fill(Color.primary.opacity(0.04))
                        .frame(height: 140)
                }
                .shimmering()
            }
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Spacer()
        }
    }

    private func deleteItem() {
        let itemToDelete = viewModel.item
        let itemID = itemToDelete.id
        let itemType = itemToDelete.type ?? .movie
        let network = itemToDelete.cachedNetwork
        let genres = itemToDelete.cachedGenres
        let lang = itemToDelete.cachedLanguage
        let badge = itemToDelete.storedSmartBadgeLabel
        // let container = modelContext.container

        withAnimation {
            isDeleted = true
            FeedbackManager.shared.trigger(.removeFromLibrary)
        }

        dismiss()

        // Use a slightly longer delay to ensure dismissal completes before deletion
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationManager.shared.cancelNotification(id: itemID, type: itemType)
            
            let container = modelContext.container
            Task.detached {
                let backgroundService = BackgroundDataService(modelContainer: container)
                await backgroundService.deleteMediaItem(id: itemID)
                
                let sync = DiscoverySyncService(modelContainer: container)
                await sync.updateItemDeleted(network: network, genres: genres, language: lang, badge: badge)
                
                await MainActor.run {
                    MediaStateService.shared.postMediaStateChanged()
                }
            }
        }
    }

}
