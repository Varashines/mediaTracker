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
            
            effectiveThemeColor
                .opacity(colorScheme == .dark ? 0.25 : 0.1)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: effectiveThemeColor)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                    headerSection
                    tmdbWarningSection
                    castAndTrackingSection
                }
                .padding(.horizontal, AppTheme.Spacing.xLarge)
                .padding(.vertical, AppTheme.Spacing.section)
            }
            .scrollBounceBehavior(.basedOnSize)
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
                        CastSectionViewNew(
                            cast: viewModel.item.displayCast,
                            themeColor: effectiveThemeColor
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
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(color.gradient)
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                Spacer()
            }
            .padding(.leading, 8)
            
            content
                .padding(24)
                .background {
                    if #available(macOS 26.0, *) {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.clear)
                            .glassEffect(.regular, in: .rect(cornerRadius: 24))
                            .opacity(scheme == .dark ? 0.4 : 0.6)
                    } else {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(scheme == .dark ? 0.4 : 0.6))
                    }
                }
                .background(color.opacity(scheme == .dark ? 0.05 : 0.02))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(scheme == .dark ? 0.1 : 0.2), lineWidth: 0.5)
                }
        }
    }
}
