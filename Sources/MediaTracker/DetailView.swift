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
            .animation(.easeInOut(duration: 0.8), value: effectiveThemeColor)
            
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
                floatingActionBar
                    .padding(.bottom, 24)
            }
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
                } else {
                    if let context = viewModel.item.modelContext {
                        SaveCoordinator.shared.requestSave(context)
                    }
                    NotificationCenter.default.post(
                        name: .mediaStateChanged,
                        object: nil,
                        userInfo: ["itemID": viewModel.item.persistentModelID]
                    )
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
                    NotificationCenter.default.post(name: .mediaStateChanged, object: nil)
                }
            }
        }
    }

    // MARK: - Floating Action Bar View
    private var floatingActionBar: some View {
        HStack(spacing: 16) {
            Button {
                showingCollectionPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                    Text("Collection")
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add to Collection")
            
            Divider()
                .frame(height: 14)
            
            Button {
                viewModel.refreshData(force: true)
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Refresh")
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshing)
            
            Divider()
                .frame(height: 14)
            
            Button(role: .destructive) {
                deleteItem()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Remove")
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.red)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 10, y: 5)
        }
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
    }
}

/// A minimal, modular container for detail sections.
struct ModularSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) var scheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.7))
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .kerning(0.8)
                Spacer()
            }
            .padding(.leading, 4)
            
            content
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(scheme == .dark ? 0.4 : 0.6))
                }
                .background(color.opacity(scheme == .dark ? 0.05 : 0.02) as Color)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
