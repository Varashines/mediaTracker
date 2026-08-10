import SwiftData
import SwiftUI

struct DetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sleepManager) private var sleepManager

    @State private var viewModel: DetailViewModel
    @State private var showSeasons = false
    @State private var showCast = false
    @State private var showRecommendations = false
    @State private var showingCollectionPicker = false
    @State private var showDeleteConfirmation = false
    @State private var showNavTitle = false
    @State private var showMoodBanner = false
    @State private var showSharePreview = false
    @State private var isHoveringRefresh = false
    @State private var isHoveringShare = false
    @State private var isHoveringDelete = false
    @State private var isTitleCopied = false
    @State private var titleCopiedTask: Task<Void, Never>?


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
                AppTheme.Colors.neutralBackground(for: colorScheme).ignoresSafeArea()
            } else {
                contentOverlay
            }

        }
    }

    @ViewBuilder
    private var backgroundMesh: some View {
        ZStack {
            AppTheme.Colors.neutralBackground(for: colorScheme)
                .ignoresSafeArea()

            if viewModel.hasDerivedThemeColor {
                // Layer 2+3: Atmospheric poster bloom. Static radial gradients only —
                // a full-window MeshGradient re-rasterizes on every scroll frame.
                if AppThemeCoordinator.isReducingVisualEffects {
                    reducedAtmosphere
                } else {
                    atmosphericGradients
                }
            }
        }
    }

    @ViewBuilder
    private var reducedAtmosphere: some View {
        viewModel.themeColor.opacity(colorScheme == .dark ? 0.14 : 0.09)
            .ignoresSafeArea()
        if let muted = viewModel.mutedThemeColor {
            muted.opacity(colorScheme == .dark ? 0.05 : 0.03)
                .ignoresSafeArea()
        }
    }

    private var atmosphericGradients: some View {
        ZStack {
            // Layer 2: Radial bloom from top-right (keeps the poster side clean)
            RadialGradient(
                colors: [
                    viewModel.themeColor.luminousAccent(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.13 : 0.22),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 700
            )
            .ignoresSafeArea()

            // Layer 3: Subtle counter-bloom from bottom-right
            if let muted = viewModel.mutedThemeColor {
                RadialGradient(
                    colors: [
                        muted.hueShift(by: 0.08).luminousAccent(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.05 : 0.08),
                        .clear
                    ],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 500
                )
                .ignoresSafeArea()
            }

            topChrome
        }
    }

    /// Layer 4: Narrow top-edge chrome so the poster color "bleeds" into the toolbar area.
    private var topChrome: some View {
        LinearGradient(
            colors: [
                viewModel.themeColor.luminousAccent(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.10 : 0.18),
                .clear
            ],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.28)
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var contentOverlay: some View {
        ZStack {
            backgroundMesh

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
                    headerSection
                    if showMoodBanner {
                        MoodCaptureBanner(
                            mediaType: viewModel.item.type,
                            onSelectMood: { mood in
                                viewModel.item.mood = mood.rawValue
                                viewModel.item.commitChange(dirty: [.badge])
                                FeedbackManager.shared.trigger(.moodSelected(mood))
                                AppErrorState.shared.showToast("Mood: \(mood.rawValue)", style: .info)
                                showMoodBanner = false
                            },
                            onDismiss: {
                                showMoodBanner = false
                            }
                        )
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        .if(!AppThemeCoordinator.isReducingVisualEffects) {
                            $0.transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    tmdbWarningSection
                    castAndTrackingSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.vertical, AppTheme.Spacing.section)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > (AppTheme.Spacing.section - 30)
            } action: { _, shouldShow in
                if showNavTitle != shouldShow {
                    showNavTitle = shouldShow
                }
            }

            floatingActionBar
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 16)
            .allowsHitTesting(!showDeleteConfirmation && !showSharePreview)

            Button("") { dismiss() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .hidden()
        }
        .overlay {
            if showDeleteConfirmation {
                deleteConfirmationOverlay
                    .transition(.opacity)
            }
            if showSharePreview {
                SharePreviewPopup(
                    item: viewModel.item,
                    onDismiss: { withAnimation(AppTheme.Animation.springSnappy) { showSharePreview = false } }
                )
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(AppTheme.Animation.springSnappy, value: showSharePreview)
        .toolbar { detailToolbar }
        .toolbar(sleepManager.isAsleep ? .hidden : .visible, for: .windowToolbar)
        .navigationTitle(sleepManager.isAsleep ? "" : (showNavTitle ? viewModel.item.title : "Details"))
        .onAppear {
            viewModel.refreshData()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                showSeasons = true
                try? await Task.sleep(nanoseconds: 50_000_000)
                showCast = true
                try? await Task.sleep(nanoseconds: 50_000_000)
                showRecommendations = true
            }
        }
        .onDisappear {
            viewModel.cancelTasks()
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
                .frame(minWidth: 350, maxWidth: 450)
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
        .onChange(of: colorScheme) { _, newScheme in
            viewModel.refreshSchemeColors(for: newScheme)
        }
        .tint(effectiveThemeColor)
        .background {
            keyboardShortcutButtons.opacity(0)
        }
    }

    private var effectiveThemeColor: Color {
        viewModel.themeColor
    }

    private var keyboardShortcutButtons: some View {
        Group {
            Button("") {
                if viewModel.item.type == .tvShow {
                    if let marked = viewModel.markNextEpisodeWatched() {
                        FeedbackManager.shared.trigger(.markWatched)
                        AppErrorState.shared.showToast("Marked S\(marked.seasonNumber) • E\(marked.episodeNumber) watched", style: .success)
                    } else {
                        AppErrorState.shared.showToast("All episodes watched", style: .info)
                    }
                } else {
                    viewModel.toggleWatched()
                    FeedbackManager.shared.trigger(.markWatched)
                    AppErrorState.shared.showToast(
                        viewModel.item.state == .completed ? "Marked as watched" : "Moved to wishlist",
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
    }

    private var headerSection: some View {
        MediaHeaderView(
            item: viewModel.item,
            themeColor: effectiveThemeColor,
            watchProviders: viewModel.watchProviders,
            onStatusChange: { newState in
                if newState == .completed {
                    viewModel.markAllAsWatched()
                } else {
                    if let context = viewModel.item.modelContext {
                        SaveCoordinator.shared.requestSave(context)
                    }
                    MediaStateService.shared.postMediaStateChanged(itemID: viewModel.item.persistentModelID)
                }
            },
            posterOptions: viewModel.posterOptions,
            isCustomPoster: viewModel.isCustomPoster,
            onSelectPoster: { url in viewModel.selectPoster(url: url) },
            onResetPoster: { viewModel.resetToDefaultPoster() },
            logoOptions: viewModel.logoOptions,
            isCustomLogo: viewModel.isCustomLogo,
            onSelectLogo: { url in viewModel.selectLogo(url: url) },
            onResetLogo: { viewModel.resetToDefaultLogo() },
            onMoodChanged: { mood in
                viewModel.item.mood = mood?.rawValue
                viewModel.item.commitChange(dirty: [.badge])
                if let mood {
                    FeedbackManager.shared.trigger(.moodSelected(mood))
                } else {
                    FeedbackManager.shared.trigger(.moodCleared)
                }
            },
            accentColor: viewModel.highContrastAccentColor,
            bgAccentColor: viewModel.luminousAccentColor
        )
    }

    @ViewBuilder
    private var tmdbWarningSection: some View {
        let hasNoGenres = viewModel.item.type == .movie && viewModel.item.cachedGenres.isEmpty
        let hasNoNetwork = viewModel.item.type == .tvShow && viewModel.item.cachedNetwork == nil

        if hasNoGenres || hasNoNetwork {
            if !APIClient.shared.isTMDBConfigured {
                HStack(spacing: AppTheme.Spacing.tiny) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(Color.semanticGold(for: colorScheme))
                    Text("Please add your TMDB API Key in Settings to see more details.")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppTheme.Spacing.small)
                .padding(.vertical, AppTheme.Spacing.micro)
                .background(
                    Capsule()
                        .fill(Color.semanticGold(for: colorScheme).opacity(0.12))
                )
            }
        }
    }

    @ViewBuilder
    private var castAndTrackingSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            // 1. TV TRACKING (Modular Card)
            if showSeasons, viewModel.item.type == .tvShow, let tv = viewModel.item.tvShowDetails {
                ModularSection(title: "Seasons & Episodes", icon: "square.stack.3d.down.right.fill", color: effectiveThemeColor) {
                    TVTrackingView(
                        tvDetails: tv,
                        themeColor: effectiveThemeColor,
                        isRefreshing: viewModel.isRefreshing,
                        onWatchedToggle: {
                            viewModel.item.lastInteractionDate = Date()
                            viewModel.item.syncCachedProperties(dirty: [.progress, .badge])
                        },
                        onSeasonSelected: { season in viewModel.fetchEpisodes(for: season) },
                        onSeasonCompleted: {
                            // Handled via badge/haptic
                        }
                    )
                    .padding(.top, 4)
                }
            }

            // 2. TOP CAST (Modular Card)
            if showCast, !viewModel.item.displayCast.isEmpty {
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
            if showRecommendations, MooreMetricsService.shared.isConfigured {
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
                                Image(systemName: "rectangle.stack.badge.sparkles")
                                    .font(.system(size: 16))
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
                        .contentShape(Capsule())
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
            if !showSeasons {
                DetailSkeletonView(
                    needsTV: viewModel.item.type == .tvShow,
                    hasCast: !viewModel.item.displayCast.isEmpty
                )
                .shimmering()
            }
        }
        .animation(AppTheme.Animation.springGentle, value: showSeasons)
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            HStack(spacing: 0) {
                Button {
                    viewModel.refreshData(force: true)
                } label: {
                    Group {
                        if viewModel.isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(isHoveringRefresh ? Color.primary.opacity(0.08) : .clear)
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(viewModel.isRefreshing)
                .keyboardShortcut("r", modifiers: [.command])
                .help("Refresh metadata")
                .accessibilityLabel("Refresh metadata")
                .onHover { isHoveringRefresh = $0 }

                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 2)

                Button {
                    withAnimation(AppTheme.Animation.springSnappy) { showSharePreview = true }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(isHoveringShare ? Color.primary.opacity(0.08) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .keyboardShortcut("s", modifiers: .command)
                .help("Share collectible card (⌘S)")
                .accessibilityLabel("Share collectible card")
                .onHover { isHoveringShare = $0 }

                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 2)

                Button(role: .destructive) {
                    if AppThemeCoordinator.isReducingVisualEffects {
                        showDeleteConfirmation = true
                    } else {
                        withAnimation(AppTheme.Animation.springSnappy) {
                            showDeleteConfirmation = true
                        }
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.semanticRed(for: colorScheme))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(isHoveringDelete ? Color.red.opacity(0.12) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .keyboardShortcut(.delete, modifiers: [.command])
                .sensoryFeedback(.error, trigger: showDeleteConfirmation)
                .help("Delete from library")
                .accessibilityLabel("Delete from library")
                .accessibilityAddTraits(.isButton)
                .onHover { isHoveringDelete = $0 }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(AppThemeCoordinator.isReducingVisualEffects
                        ? AnyShapeStyle(AppTheme.Colors.neutralBackground(for: colorScheme))
                        : AnyShapeStyle(.ultraThinMaterial))
            )
            .overlay(
                Capsule()
                    .stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 0.5)
            )
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

        isTitleCopied = true
        titleCopiedTask?.cancel()
        titleCopiedTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            isTitleCopied = false
        }
    }

    @ViewBuilder
    private var floatingActionBar: some View {
        HStack(spacing: 4) {
            if viewModel.trailerKey != nil {
                actionChip(
                    icon: "play.rectangle.fill",
                    label: "Trailer",
                    action: openTrailer
                )
            }

            actionChip(
                icon: "folder.badge.plus",
                label: "Add to Collection",
                action: { showingCollectionPicker = true }
            )
            .keyboardShortcut("l", modifiers: [.command])

            if isTitleCopied {
                actionChip(
                    icon: "checkmark",
                    label: "Copied",
                    action: {}
                )
            } else {
                actionChip(
                    icon: "doc.on.doc",
                    label: "Copy Title",
                    action: copyTitle
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            ZStack {
                Capsule()
                    .fill(AppThemeCoordinator.isReducingVisualEffects
                        ? AnyShapeStyle(AppTheme.Colors.neutralBackground(for: colorScheme))
                        : AnyShapeStyle(.ultraThinMaterial))

                if viewModel.hasDerivedThemeColor {
                    Capsule()
                        .fill(effectiveThemeColor.opacity(colorScheme == .dark ? 0.22 : 0.14))
                }
            }
        }
        .overlay(
            Capsule()
                .stroke(
                    viewModel.hasDerivedThemeColor
                        ? effectiveThemeColor.opacity(colorScheme == .dark ? 0.35 : 0.25)
                        : Color.primary.opacity(0.08),
                    lineWidth: 0.8
                )
        )
        .shadow(color: Color.black.opacity(0.20), radius: 8, y: 3)
        .shadow(
            color: viewModel.hasDerivedThemeColor
                ? effectiveThemeColor.opacity(colorScheme == .dark ? 0.30 : 0.18)
                : .clear,
            radius: 16, y: 2
        )
    }

    private func actionChip(icon: String, label: String, action: @escaping () -> Void) -> some View {
        ActionChipButton(icon: icon, label: label, action: action)
    }

    @ViewBuilder
    private var deleteConfirmationOverlay: some View {
        ZStack {
            Group {
                if AppThemeCoordinator.isReducingVisualEffects {
                    Color.black.opacity(colorScheme == .dark ? 0.4 : 0.25)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { showDeleteConfirmation = false }
                } else {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .overlay(Color.black.opacity(colorScheme == .dark ? 0.25 : 0.12))
                        .contentShape(Rectangle())
                        .onTapGesture { showDeleteConfirmation = false }
                }
            }
            .transition(.opacity)

            VStack(spacing: AppTheme.Spacing.compact) {
                if let posterURL = viewModel.item.effectivePosterURL, let url = URL(string: posterURL) {
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
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text("will be removed")
                    .font(AppTheme.Font.body)
                    .foregroundStyle(.secondary)

                HStack(spacing: 24) {
                    Button {
                        showDeleteConfirmation = false
                    } label: {
                        Text("No")
                            .font(AppTheme.Font.bodyMedium)
                            .foregroundStyle(Color.semanticGreen(for: colorScheme))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())

                    Button {
                        deleteItem()
                    } label: {
                        Text("Yes")
                            .font(AppTheme.Font.bodyMedium)
                            .foregroundStyle(Color.semanticRed(for: colorScheme))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
                .padding(.top, 6)
            }
            .padding(AppTheme.Spacing.large)
            .frame(maxWidth: 280)
            .background {
                GlassCard(color: effectiveThemeColor, material: .ultraThinMaterial, cornerRadius: AppTheme.Radius.large, shadowed: false) {
                    Color.clear
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
            .shadow(color: effectiveThemeColor.opacity(colorScheme == .dark ? 0.2 : 0.08), radius: 16, y: 4)
            .padding(.horizontal, 80)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    private func deleteItem() {
        guard !viewModel.item.isDeleted else { return }
        let itemToDelete = viewModel.item
        let itemID = itemToDelete.id
        let itemType = itemToDelete.type ?? .movie
        let network = itemToDelete.cachedNetwork
        let genres = itemToDelete.cachedGenres
        let lang = itemToDelete.cachedLanguage
        let badge = itemToDelete.storedSmartBadgeLabel
        let providers = itemToDelete.cachedWatchProviders
        let persistentID = itemToDelete.persistentModelID

        showDeleteConfirmation = false
        FeedbackManager.shared.trigger(.removeFromLibrary)

        // Soft-delete so the user can undo within the 5s window.
        itemToDelete.softDelete()
        NotificationManager.shared.cancelNotification(id: itemID, type: itemType)

        let undo: @MainActor () -> Void = { [modelContext] in
            guard let live = modelContext.model(for: persistentID) as? MediaItem, !live.isDeleted else { return }
            live.restoreFromSoftDelete()
        }

        AppErrorState.shared.showToast(
            "Removed \"\(itemToDelete.title)\"",
            style: .warning,
            duration: 5,
            undoAction: undo
        )

        Task {
            try? await Task.sleep(for: .milliseconds(250))
            dismiss()
        }

        // Discovery entity counts are only adjusted after the undo window closes,
        // so an undo within 5s leaves the hub counts intact.
        let container = modelContext.container
        Task.detached(priority: .background) {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { return }
            let context = ModelContext(container)
            if let live = context.model(for: persistentID) as? MediaItem, live.isSoftDeleted {
                let backgroundService = BackgroundDataService(modelContainer: container)
                await backgroundService.deleteMediaItem(id: itemID)

                let sync = DiscoverySyncService(modelContainer: container)
                await sync.updateItemDeleted(network: network, genres: genres, language: lang, badge: badge, providers: providers)

                try? await Task.sleep(for: .seconds(0.3))
                await MainActor.run {
                    MediaStateService.shared.postMediaStateChanged()
                }
            }
        }
    }

}

private struct ActionChipButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .imageScale(.small)
                Text(label)
                    .font(AppTheme.Font.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(isHovered
                        ? AnyShapeStyle(.ultraThinMaterial)
                        : AnyShapeStyle(Color.clear))
                    .overlay {
                        if isHovered {
                            Capsule()
                                .stroke(AppTheme.Colors.strokeHover(for: colorScheme), lineWidth: 0.5)
                        }
                    }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .primary : .secondary)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.springSnappy) {
                isHovered = hovering
            }
        }
    }
}
