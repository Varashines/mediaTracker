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
        .scrollBounceBehavior(.basedOnSize)
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
        .tint(viewModel.contrastThemeColor)
        .appBackground(
            tint: viewModel.vibrantThemeColor, 
            warmTint: viewModel.warmThemeColor, 
            coolTint: viewModel.coolThemeColor, 
            disableBrandBackground: true
        )
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if themeStyle == .brand {
            appAccent.brandBackground(for: colorScheme)
                .ignoresSafeArea()
        } else {
            Color(NSColor.windowBackgroundColor)
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
        VStack(alignment: .leading, spacing: 32) {
            if showHeavyContent {
                // 1. TV TRACKING (Modular Card)
                if viewModel.item.type == .tvShow, let tv = viewModel.item.tvShowDetails {
                    ModularSection(title: "Seasons & Episodes", icon: "square.stack.3d.down.right.fill", color: viewModel.themeColor) {
                        TVTrackingView(
                            tvDetails: tv,
                            themeColor: viewModel.themeColor,
                            isRefreshing: viewModel.isRefreshing,
                            onWatchedToggle: { viewModel.checkOverallCompletion() },
                            onSeasonSelected: { season in viewModel.fetchEpisodes(for: season) }
                        )
                        .padding(.top, 4)
                    }
                }

                // 2. TOP CAST (Modular Card)
                if !viewModel.item.displayCast.isEmpty {
                    ModularSection(title: "Top Cast", icon: "person.2.fill", color: viewModel.themeColor) {
                        CastSectionViewNew(
                            cast: viewModel.item.displayCast,
                            themeColor: viewModel.themeColor
                        ) { actorName in
                            onSearchActor?(actorName)
                        }
                    }
                }
            } else {
                // SKELETON LOADER
                VStack(spacing: 24) {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.primary.opacity(0.04))
                        .frame(height: 180)
                    RoundedRectangle(cornerRadius: 20)
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

/// A premium, modular container for cinematic detail sections.
struct ModularSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) var scheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color.gradient)
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
            }
            .padding(.leading, 4)
            
            content
                .padding(20)
                .background(Color.primary.opacity(scheme == .dark ? 0.05 : 0.03))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                }
        }
    }
}
