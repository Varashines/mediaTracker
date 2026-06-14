import SwiftData
import SwiftUI

struct DetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sleepManager) private var sleepManager

    @State private var viewModel: DetailViewModel
    @State private var showHeavyContent = false
    @State private var showingCollectionPicker = false
    @State private var showDeleteConfirmation = false
    @State private var showNavTitle = false

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
            if viewModel.item.modelContext == nil {
                AppTheme.Colors.background(for: colorScheme).ignoresSafeArea()
            } else {
                contentOverlay
            }
        }
    }

    @ViewBuilder
    private var contentOverlay: some View {
        ZStack {
            let p = viewModel.vibrantThemeColor
            let hasPoster = viewModel.item.posterURL != nil

            // Use neutral bg when poster exists, palette bg when no poster
            Group {
                if hasPoster {
                    Color(white: colorScheme == .dark ? 0.11 : 0.96)
                } else {
                    AppTheme.Colors.background(for: colorScheme)
                }
            }
            .overlay(p.opacity(colorScheme == .dark ? 0.15 : 0.12))
            .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                    headerSection
                        .background(alignment: .top) {
                            GeometryReader { geo in
                                let frame = geo.frame(in: .named("detailScroll"))
                                Color.clear
                                    .onChange(of: frame.minY) { _, newValue in
                                        showNavTitle = newValue < -50
                                    }
                                    .onAppear {
                                        showNavTitle = frame.minY < -50
                                    }
                            }
                        }
                    tmdbWarningSection
                    castAndTrackingSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.vertical, AppTheme.Spacing.section)
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.always)
            .coordinateSpace(name: "detailScroll")
            .saturation(showDeleteConfirmation ? 0.3 : 1)
            .blur(radius: showDeleteConfirmation ? 5 : 0)

        }
        .overlay {
            if showDeleteConfirmation {
                deleteConfirmationOverlay
                    .transition(.opacity)
            }
        }
        .toolbar { detailToolbar }
        .toolbarBackground(sleepManager.isAsleep ? .hidden : .automatic, for: .windowToolbar)
        .toolbar(sleepManager.isAsleep ? .hidden : .visible, for: .windowToolbar)
        .navigationTitle(sleepManager.isAsleep ? "" : showNavTitle ? viewModel.item.title : "Details")
        .onAppear {
            viewModel.refreshData()
            Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                showHeavyContent = true
            }
        }
        .userActivity("com.vara.MediaTracker.viewItem") { activity in
            activity.title = viewModel.item.title
            activity.userInfo = ["id": viewModel.item.id]
            activity.isEligibleForSearch = true
            activity.persistentIdentifier = viewModel.item.id
            activity.requiredUserInfoKeys = ["id"]
        }
        .sheet(isPresented: $showingCollectionPicker) {
            CollectionPickerView(item: viewModel.item)
        }
        .onChange(of: MediaStateService.shared.refreshedItemID) { _, newID in
            if let id = newID, id == viewModel.item.id {
                viewModel.refreshLocalItem()
            }
        }
        .onChange(of: viewModel.item.themeColorHex) { _, newHex in
            if newHex != nil {
                viewModel.updateThemeColor()
            }
        }
        .tint(effectiveThemeColor)
        .background {
            Group {
                Button("") {
                    if viewModel.item.type == .tvShow {
                        viewModel.markNextEpisodeWatched()
                        FeedbackManager.shared.trigger(.markWatched)
                        AppErrorState.shared.showToast("Next episode marked", style: .success)
                    } else {
                        viewModel.toggleWatched()
                        let isCompleted = viewModel.item.state == .completed
                        FeedbackManager.shared.trigger(isCompleted ? .markWatched : .stateChange)
                        AppErrorState.shared.showToast(
                            isCompleted ? "Marked as watched" : "Moved to wishlist",
                            style: .success
                        )
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
                
                Button("") {
                    viewModel.cycleStatus()
                    AppErrorState.shared.showToast(
                        "Moved to \(viewModel.item.state?.displayName ?? "new status")",
                        style: .success
                    )
                }
                .keyboardShortcut("w", modifiers: [])
            }
            .opacity(0)
        }
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
                    .font(AppTheme.Font.caption)
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
                            onWatchedToggle: {
                                viewModel.item.lastInteractionDate = Date()
                                viewModel.item.syncCachedProperties()
                            },
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

                // 3. RECOMMENDATIONS (Modular Card)
                if MooreMetricsService.shared.isConfigured {
                    let detailTraits = viewModel.debugSelectedTraits
                    let detailTitle: String = {
                        if !detailTraits.isEmpty {
                            return "You Might Also Like  ·  Top traits: \(detailTraits.joined(separator: ", "))"
                        }
                        return "You Might Also Like"
                    }()
                    ModularSection(title: detailTitle, icon: "sparkles", color: effectiveThemeColor) {
                    if viewModel.isLoadingRecommendations {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Finding recommendations...")
                                .font(AppTheme.Font.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    } else if viewModel.recommendations.isEmpty {
                        Button {
                            viewModel.fetchRecommendations()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(AppTheme.Font.body)
                                Text("Discover similar shows")
                                    .font(AppTheme.Font.caption)
                            }
                            .foregroundStyle(effectiveThemeColor.highContrastAccent(colorScheme: colorScheme))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(effectiveThemeColor.opacity(colorScheme == .dark ? 0.15 : 0.12))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        RecommendationSectionView(
                            recommendations: viewModel.recommendations,
                            themeColor: effectiveThemeColor
                        ) { showName in
                            onSearchActor?(showName)
                        }
                    }
                }
            }
            } else if viewModel.item.type == .tvShow || !viewModel.item.displayCast.isEmpty {
                DetailSkeletonView(
                    needsTV: viewModel.item.type == .tvShow,
                    hasCast: !viewModel.item.displayCast.isEmpty
                )
            }
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            HStack(spacing: 6) {
                Button {
                    viewModel.refreshData(force: true)
                } label: {
                    if viewModel.isRefreshing {
                        ProgressView().controlSize(.small)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 28, height: 28)
                    }
                }
                .buttonStyle(.plain)
                .background(Capsule().fill(.ultraThinMaterial))
                .clipShape(.capsule)
                .frame(width: 32, height: 32)
                .disabled(viewModel.isRefreshing)
                .keyboardShortcut("r", modifiers: [.command])
                .help("Refresh metadata")

                Button(role: .destructive) {
                    withAnimation(AppTheme.Animation.springSnappy) {
                        showDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(Capsule().fill(.ultraThinMaterial))
                .clipShape(.capsule)
                .frame(width: 32, height: 32)
                .keyboardShortcut(.delete, modifiers: [.command])
                .help("Delete from library")

                Menu {
                    if viewModel.trailerKey != nil {
                        Button("Play Trailer") { openTrailer() }
                    }
                    Button("Add to Collection") { showingCollectionPicker = true }
                        .keyboardShortcut("l", modifiers: [.command])
                    Button("Copy Title") { copyTitle() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 32, height: 32)
            }
        }
    }

    // MARK: - Actions

    private func openTrailer() {
        guard let key = viewModel.trailerKey,
              let url = URL(string: "https://www.youtube.com/watch?v=\(key)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyTitle() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.item.title, forType: .string)
        AppErrorState.shared.showToast("Title copied", style: .success)
    }

    @ViewBuilder
    private var deleteConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.4 : 0.25)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDeleteConfirmation = false
                    }
                }
                .transition(.opacity)

            VStack(spacing: 10) {
                if let posterURL = viewModel.item.posterURL, let url = URL(string: posterURL) {
                    CachedImage(url: url, targetSize: AppTheme.Thumbnail.tiny) { _ in } placeholder: {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.1))
                    }
                    .frame(width: 80, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 4)
                }

                Text("Are you sure?")
                    .font(AppTheme.Font.subtitle)
                    .foregroundStyle(.primary)

                Text(viewModel.item.title)
                    .font(AppTheme.Font.title3)
                    .foregroundStyle(effectiveThemeColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text("will be removed")
                    .font(AppTheme.Font.body)
                    .foregroundStyle(.secondary)

                HStack(spacing: 24) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDeleteConfirmation = false
                        }
                    } label: {
                        Text("No")
                            .font(AppTheme.Font.bodyMedium)
                            .foregroundStyle(Color.semanticGreen(for: colorScheme))
                    }
                    .buttonStyle(.plain)

                    Button {
                        deleteItem()
                    } label: {
                        Text("Yes")
                            .font(AppTheme.Font.bodyMedium)
                            .foregroundStyle(Color.semanticRed(for: colorScheme))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
            .padding(20)
            .frame(maxWidth: 280)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                            .fill(effectiveThemeColor.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                            .strokeBorder(LinearGradient(
                                colors: [effectiveThemeColor.opacity(0.35), effectiveThemeColor.opacity(0.08)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.3 : 0.15),
                radius: 8,
                x: 0,
                y: 4
            )
            .padding(.horizontal, 80)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
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

        showDeleteConfirmation = false
        FeedbackManager.shared.trigger(.removeFromLibrary)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dismiss()
        }

        Task {
            try? await Task.sleep(for: .seconds(0.75))
            NotificationManager.shared.cancelNotification(id: itemID, type: itemType)
            
            let container = modelContext.container
            Task.detached {
                let backgroundService = BackgroundDataService(modelContainer: container)
                await backgroundService.deleteMediaItem(id: itemID)
                
                let sync = DiscoverySyncService(modelContainer: container)
                await sync.updateItemDeleted(network: network, genres: genres, language: lang, badge: badge)
                
                try? await Task.sleep(for: .seconds(0.3))
                await MainActor.run {
                    MediaStateService.shared.postMediaStateChanged()
                }
            }
        }
    }

}
