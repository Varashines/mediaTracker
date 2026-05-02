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
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
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
        }
        .onDisappear { isAppeared = false }
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

            viewModel.themeColor
                .opacity(isAppeared ? (colorScheme == .dark ? 0.4 : 0.25) : 0)
                .blur(radius: isAppeared ? 120 : 80)
                .scaleEffect(isAppeared ? 1.1 : 0.9)
                .ignoresSafeArea()

            LinearGradient(
                gradient: Gradient(colors: [
                    viewModel.themeColor.opacity(isAppeared ? (colorScheme == .dark ? 0.3 : 0.2) : 0),
                    .clear
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        MediaHeaderView(
            item: viewModel.item,
            themeColor: viewModel.themeColor,
            namespace: namespace
        ) { newState in
            if newState == .completed {
                viewModel.markAllAsWatched()
            }
        }
        .onAppear {
            viewModel.updateThemeColor()
            viewModel.refreshData()
        }
    }

    @ViewBuilder
    private var tmdbWarningSection: some View {
        let hasNoGenres = viewModel.item.type == .movie && viewModel.item.movieDetails?.genres.isEmpty != false
        let hasNoStatus = viewModel.item.type == .tvShow && viewModel.item.tvShowDetails?.status == nil
        
        if hasNoGenres || hasNoStatus {
            if !APIClient.shared.isTMDBConfigured {
                Text("Please add your TMDB API Key in Settings to see more details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var castAndTrackingSection: some View {
        LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            if !viewModel.item.displayCast.isEmpty {
                Divider()

                DisclosureGroup(isExpanded: $isCastExpanded) {
                    CastSectionViewNew(
                        cast: viewModel.item.displayCast,
                        themeColor: viewModel.themeColor
                    ) { actorName in
                        onSearchActor?(actorName)
                    }
                    .padding(.top, AppTheme.Spacing.tiny)
                } label: {
                    HStack {
                        Text("Cast")
                            .font(.title3.bold())
                        Spacer()
                        Text("\(viewModel.item.displayCast.count)")
                            .font(.caption.bold())
                            .padding(.horizontal, AppTheme.Spacing.tiny)
                            .padding(.vertical, 2)
                            .background(viewModel.themeColor.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                .disclosureGroupStyle(CustomDisclosureStyle(buttonColor: viewModel.themeColor))
                .padding(.horizontal, AppTheme.Spacing.tiny)
            }

            if let tv = viewModel.item.tvShowDetails {
                Divider()

                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    HStack {
                        Image(systemName: "play.tv.fill")
                            .foregroundStyle(viewModel.themeColor)
                        Text("Seasons & Episodes")
                            .font(.title3.bold())
                    }
                    .padding(.horizontal, AppTheme.Spacing.tiny)

                    TVTrackingView(
                        tvDetails: tv,
                        themeColor: viewModel.themeColor,
                        onWatchedToggle: { viewModel.checkOverallCompletion() },
                        onSeasonSelected: { season in viewModel.fetchEpisodes(for: season) }
                    )
                }
            }
            Divider()
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 16) {
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
            modelContext.delete(itemToDelete)
            try? modelContext.save()
            NotificationCenter.default.post(name: .mediaStateChanged, object: nil)

            let container = modelContext.container
            Task.detached {
                let sync = DiscoverySyncService(modelContainer: container)
                await sync.updateItemDeleted(network: network, genres: genres, language: lang)
            }
        }
    }
}
