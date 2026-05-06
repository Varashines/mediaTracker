import SwiftData
import SwiftUI

struct DetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme_style") private var themeStyle: ThemeStyle = .standard
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic

    @State private var viewModel: DetailViewModel
    @State private var isAppeared = false
    @State private var isDeleted = false
    @State private var isCastExpanded = false
    @State private var showHeavyContent = false
    @State private var breathingTrigger = false
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
            if isDeleted || viewModel.item.modelContext == nil || viewModel.item.isDeleted {
                Color(NSColor.windowBackgroundColor).ignoresSafeArea()
            } else {
                contentOverlay
            }
        }
    }

    @ViewBuilder
    private var contentOverlay: some View {
        backgroundLayer
            .animation(.spring(response: 0.8, dampingFraction: 0.85), value: isAppeared)
            .animation(.easeInOut(duration: 1.0), value: viewModel.themeColor)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                headerSection
                tmdbWarningSection
                castAndTrackingSection
            }
            .padding(AppTheme.Spacing.large)
        }
        .navigationTitle("Details")
        .toolbar { detailToolbar }
        .onAppear {
            viewModel.refreshData()
            withAnimation(.spring(response: 1.0, dampingFraction: 0.85).delay(0.1)) {
                isAppeared = true
            }
            
            // Phase 2: Navigation Animation Deferral
            Task {
                try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s delay
                withAnimation(.easeOut(duration: 0.4)) {
                    showHeavyContent = true
                }
            }
            
            // Phase 3: Breathing Ambient Glow
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                breathingTrigger.toggle()
            }
        }
        .onDisappear { isAppeared = false }
        .sheet(isPresented: $showingCollectionPicker) {
            CollectionPickerView(item: viewModel.item)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaItemRefreshed)) { notification in
            if let id = notification.userInfo?["id"] as? String, id == viewModel.item.id {
                viewModel.refreshLocalItem()
            }
        }
        .tint(viewModel.themeColor)
        .appBackground(tint: viewModel.themeColor, disableBrandBackground: true)
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        ZStack {
            if themeStyle == .brand {
                appAccent.brandBackground(for: colorScheme)
                    .ignoresSafeArea()
            } else {
                Color(NSColor.windowBackgroundColor)
                    .ignoresSafeArea()
            }

            // Phase 3: Breathing Ambient Glow (Optimized Radial Gradient)
            let color = viewModel.themeColor
            
            RadialGradient(
                gradient: Gradient(colors: [
                    color.opacity(isAppeared ? (colorScheme == .dark ? 0.35 : 0.2) : 0),
                    Color.clear
                ]),
                center: .topLeading,
                startRadius: 0,
                endRadius: breathingTrigger ? 800 : 600
            )
            .saturation(1.3)
            .ignoresSafeArea()
            
            RadialGradient(
                gradient: Gradient(colors: [
                    color.opacity(isAppeared ? (colorScheme == .dark ? 0.25 : 0.15) : 0),
                    Color.clear
                ]),
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: breathingTrigger ? 700 : 500
            )
            .saturation(1.3)
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        MediaHeaderView(
            item: viewModel.item,
            themeColor: viewModel.themeColor,
            viewModel: viewModel,
            namespace: namespace,
            onStatusChange: { newState in
                if newState == .completed {
                    viewModel.markAllAsWatched()
                }
            }
        )
        .onAppear {
            viewModel.updateThemeColor()
            viewModel.refreshData()
        }
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
        LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            if showHeavyContent {
                // 1. TV TRACKING (Highest Priority for Series)
                if viewModel.item.type == .tvShow, let tv = viewModel.item.tvShowDetails {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                        Text("Seasons & Episodes")
                            .font(.title3.bold())
                            .padding(.horizontal, AppTheme.Spacing.tiny)

                        TVTrackingView(
                            tvDetails: tv,
                            themeColor: viewModel.themeColor,
                            isRefreshing: viewModel.isRefreshing,
                            onWatchedToggle: { viewModel.checkOverallCompletion() },
                            onSeasonSelected: { season in viewModel.fetchEpisodes(for: season) }
                        )

                    }
                    Divider().padding(.vertical, AppTheme.Spacing.small)
                }

                // 2. TOP CAST (High Priority for Both)
                if !viewModel.item.displayCast.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                        HStack {
                            Text("Top Cast")
                                .font(.title3.bold())
                            Spacer()
                            Text("\(viewModel.item.displayCast.count)")
                                .font(.caption.bold())
                                .padding(.horizontal, AppTheme.Spacing.tiny)
                                .padding(.vertical, 2)
                                .background(viewModel.themeColor.opacity(0.2))
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, AppTheme.Spacing.tiny)

                        CastSectionViewNew(
                            cast: viewModel.item.displayCast,
                            themeColor: viewModel.themeColor
                        ) { actorName in
                            onSearchActor?(actorName)
                        }
                    }
                    Divider().padding(.vertical, AppTheme.Spacing.small)
                }
            } else {
                // SKELETON LOADER (Perceived Speed)
                VStack(alignment: .leading, spacing: 30) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 150)
                    
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 120)
                }
                .padding(.top, 20)
                .shimmering()
            }
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 16) {
                Button {
                    showingCollectionPicker = true
                } label: {
                    Label("Add to Collection", systemImage: "folder.badge.plus")
                }
                .help("Add to Collection")

                Button {
                    viewModel.refreshData(force: true)
                } label: {
                    if viewModel.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(viewModel.isRefreshing)

                Button(role: .destructive) {
                    deleteItem()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    private func deleteItem() {
        let itemToDelete = viewModel.item
        let itemID = itemToDelete.id
        let itemType = itemToDelete.type ?? .movie
        let network = itemToDelete.cachedNetwork
        let genres = itemToDelete.cachedGenres
        let lang = itemToDelete.cachedLanguage
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
                await sync.updateItemDeleted(network: network, genres: genres, language: lang)
                
                await MainActor.run {
                    NotificationCenter.default.post(name: .mediaStateChanged, object: nil)
                }
            }
        }
    }
}
