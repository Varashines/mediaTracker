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
    @State private var showMoodBanner = false
    @State private var showingShareSheet = false
    @State private var shareImage: NSImage? = nil
    @State private var showSharePreview = false


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
    private var backgroundMesh: some View {
        let posterTheme = viewModel.themeColor
        let hasCustomTheme = viewModel.themeColor != Color.secondary.opacity(0.1)

        ZStack {
            AppTheme.Colors.background(for: colorScheme)
                .ignoresSafeArea()

            if hasCustomTheme {
                // Whole-page uniform poster theme background fill
                posterTheme.opacity(colorScheme == .dark ? 0.18 : 0.12)
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var contentOverlay: some View {
        ZStack {
            backgroundMesh

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                    headerSection
                        .background(alignment: .top) {
                            GeometryReader { geo in
                                let frame = geo.frame(in: .named("detailScroll"))
                                Color.clear
                                    .onChange(of: frame.minY) { _, newValue in
                                        let shouldShow = newValue < -50
                                        if showNavTitle != shouldShow {
                                            withAnimation(AppTheme.Animation.springSnappy) {
                                                showNavTitle = shouldShow
                                            }
                                        }
                                    }
                                    .onAppear {
                                        showNavTitle = frame.minY < -50
                                    }
                            }
                        }
                    if showMoodBanner {
                        MoodCaptureBanner(
                            mediaType: viewModel.item.type,
                            onSelectMood: { mood in
                                viewModel.item.mood = mood.rawValue
                                viewModel.item.commitChange(dirty: [.badge])
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
                .padding(.bottom, AppTheme.Spacing.tiny)
            }
            .scrollBounceBehavior(.always)
            .scrollIndicators(.hidden)
            .coordinateSpace(name: "detailScroll")

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
                    onShare: { image in
                        shareImage = image
                        showingShareSheet = true
                        withAnimation(AppTheme.Animation.springSnappy) { showSharePreview = false }
                    },
                    onDismiss: { withAnimation(AppTheme.Animation.springSnappy) { showSharePreview = false } }
                )
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(AppTheme.Animation.springSnappy, value: showSharePreview)
        .toolbar { detailToolbar }
        .toolbarBackground(sleepManager.isAsleep ? .hidden : .automatic, for: .windowToolbar)
        .toolbar(sleepManager.isAsleep ? .hidden : .visible, for: .windowToolbar)
        .navigationTitle(sleepManager.isAsleep ? "" : (showNavTitle ? viewModel.item.title : "Details"))
        .onAppear {
            viewModel.refreshData()
            Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                showHeavyContent = true
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
        .onChange(of: showingShareSheet) { _, show in
            if show, let image = shareImage {
                let picker = NSSharingServicePicker(items: [image])
                if let window = NSApp.keyWindow, let content = window.contentView {
                    picker.show(relativeTo: .zero, of: content, preferredEdge: .minY)
                }
                showingShareSheet = false
            }
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
                    viewModel.markNextEpisodeWatched()
                    FeedbackManager.shared.trigger(.markWatched)
                    AppErrorState.shared.showToast("Next episode marked", style: .success)
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
                        .foregroundStyle(.orange)
                    Text("Please add your TMDB API Key in Settings to see more details.")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppTheme.Spacing.small)
                .padding(.vertical, AppTheme.Spacing.micro)
                .background(
                    Capsule()
                        .fill(.orange.opacity(0.1))
                )
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
            } else {
                DetailSkeletonView(
                    needsTV: viewModel.item.type == .tvShow,
                    hasCast: !viewModel.item.displayCast.isEmpty
                )
                .shimmering()
            }
        }
        .animation(AppTheme.Animation.springGentle, value: showHeavyContent)
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
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(viewModel.isRefreshing)
                .keyboardShortcut("r", modifiers: [.command])
                .help("Refresh metadata")
                .accessibilityLabel("Refresh metadata")

                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 2)

                Button {
                    withAnimation(AppTheme.Animation.springSnappy) { showSharePreview = true }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .keyboardShortcut("s", modifiers: .command)
                .help("Share collectible card (⌘S)")
                .accessibilityLabel("Share collectible card")

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
                        .foregroundStyle(.red.opacity(0.85))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .keyboardShortcut(.delete, modifiers: [.command])
                .sensoryFeedback(.error, trigger: showDeleteConfirmation)
                .help("Delete from library")
                .accessibilityLabel("Delete from library")
                .accessibilityAddTraits(.isButton)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(AppThemeCoordinator.isReducingVisualEffects
                        ? AnyShapeStyle(AppTheme.Colors.background(for: colorScheme))
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

            actionChip(
                icon: "doc.on.doc",
                label: "Copy Title",
                action: copyTitle
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(AppThemeCoordinator.isReducingVisualEffects
            ? AnyShapeStyle(AppTheme.Colors.background(for: colorScheme))
            : AnyShapeStyle(.ultraThinMaterial)))
    }

    private func actionChip(icon: String, label: String, action: @escaping () -> Void) -> some View {
        ActionChipButton(icon: icon, label: label, action: action)
    }

    @ViewBuilder
    private var deleteConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.4 : 0.25)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if AppThemeCoordinator.isReducingVisualEffects {
                        showDeleteConfirmation = false
                    } else {
                        withAnimation(AppTheme.Animation.springSnappy) {
                            showDeleteConfirmation = false
                        }
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
                        if AppThemeCoordinator.isReducingVisualEffects {
                            showDeleteConfirmation = false
                        } else {
                            withAnimation(AppTheme.Animation.springSnappy) {
                                showDeleteConfirmation = false
                            }
                        }
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
            .background(
                GlassCard(color: effectiveThemeColor, material: .ultraThinMaterial, cornerRadius: AppTheme.Radius.large, shadowed: true) {
                    Color.clear
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.3 : 0.15),
                radius: 8,
                x: 0,
                y: 4
            )
            .padding(.horizontal, 80)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
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
        let providers = itemToDelete.cachedWatchProviders

        showDeleteConfirmation = false
        FeedbackManager.shared.trigger(.removeFromLibrary)

        Task {
            try? await Task.sleep(for: .milliseconds(250))
            dismiss()
        }

        Task {
            try? await Task.sleep(for: .seconds(0.75))
            NotificationManager.shared.cancelNotification(id: itemID, type: itemType)
            
            let container = modelContext.container
            Task.detached(priority: .background) {
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
            .background(isHovered ? Color.primary.opacity(0.06) : .clear)
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
