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
    @State private var showDeleteConfirmation = false
    @State private var showNavTitle = false
    @State private var isCollHovered = false
    @State private var isRefreshHovered = false
    @State private var isDeleteHovered = false

    var onSearchActor: ((String) -> Void)? = nil
    var namespace: Namespace.ID? = nil

    struct ScrollOffsetPref: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {}
    }

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
            
            // Dynamic Backdrop Gradient — full-view wash
            GeometryReader { geo in
                ZStack {
                    RadialGradient(
                        colors: [
                            effectiveThemeColor.luminousAccent(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.22 : 0.18),
                            effectiveThemeColor.luminousAccent(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.08 : 0.06),
                            .clear
                        ],
                        center: .top,
                        startRadius: 0,
                        endRadius: min(geo.size.width, geo.size.height) * 1.5
                    )
                    RadialGradient(
                        colors: [
                            effectiveThemeColor.luminousAccent(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.08 : 0.06),
                            .clear
                        ],
                        center: .bottom,
                        startRadius: 0,
                        endRadius: min(geo.size.width, geo.size.height) * 0.8
                    )
                }
                .ignoresSafeArea()
            }
            .animation(AppTheme.Animation.springGentle, value: effectiveThemeColor)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                    headerSection
                        .background(alignment: .top) {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ScrollOffsetPref.self,
                                    value: geo.frame(in: .named("detailScroll")).minY
                                )
                            }
                        }
                    tmdbWarningSection
                    castAndTrackingSection
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.vertical, AppTheme.Spacing.section)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .saturation(showDeleteConfirmation ? 0 : 1)
            .scaleEffect(showDeleteConfirmation ? 0.97 : 1)
            .coordinateSpace(name: "detailScroll")
            .onPreferenceChange(ScrollOffsetPref.self) { minY in
                showNavTitle = minY < -50
            }

            if showDeleteConfirmation {
                deleteConfirmationOverlay
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showDeleteConfirmation)
        .navigationTitle(showNavTitle ? viewModel.item.title : "Details")
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
            } else if viewModel.item.type == .tvShow || !viewModel.item.displayCast.isEmpty {
                // SKELETON LOADER — only when content exists to reveal
                VStack(spacing: AppTheme.Spacing.large) {
                    if viewModel.item.type == .tvShow {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                            .fill(Color.primary.opacity(0.04))
                            .frame(height: 180)
                    }
                    if !viewModel.item.displayCast.isEmpty {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                            .fill(Color.primary.opacity(0.04))
                            .frame(height: 140)
                    }
                }
                .shimmering()
            }
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            HStack(spacing: 14) {
                Button {
                    showingCollectionPicker = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(isCollHovered ? Color.primary.opacity(0.1) : Color.clear)
                            .frame(width: 28, height: 28)
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 15))
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(AppTheme.Animation.easeInOut) { isCollHovered = hovering }
                }

                Button {
                    viewModel.refreshData(force: true)
                } label: {
                    ZStack {
                        Circle()
                            .fill(isRefreshHovered ? Color.primary.opacity(0.1) : Color.clear)
                            .frame(width: 28, height: 28)
                        if viewModel.isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isRefreshing)
                .onHover { hovering in
                    withAnimation(AppTheme.Animation.easeInOut) { isRefreshHovered = hovering }
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(isDeleteHovered ? Color.primary.opacity(0.1) : Color.clear)
                            .frame(width: 28, height: 28)
                        Image(systemName: "trash")
                            .font(.system(size: 15))
                            .foregroundStyle(.red)
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(AppTheme.Animation.easeInOut) { isDeleteHovered = hovering }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private var deleteConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDeleteConfirmation = false
                    }
                }
                .transition(.opacity)

            VStack(spacing: 14) {
                Text("Are you sure?")
                    .font(AppTheme.Font.title3)
                    .foregroundStyle(.red)

                Text("This action will delete")
                    .font(AppTheme.Font.caption2)
                    .foregroundStyle(.secondary)

                Text(viewModel.item.title)
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(effectiveThemeColor.highContrastAccent(colorScheme: colorScheme))

                Text("from the library")
                    .font(AppTheme.Font.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 24) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDeleteConfirmation = false
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.secondary.opacity(0.5))
                            Text("Cancel")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(width: 56)
                    }
                    .buttonStyle(.plain)

                    Button {
                        deleteItem()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.red)
                            Text("Delete")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                        .frame(width: 56)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                effectiveThemeColor.opacity(0.35),
                                effectiveThemeColor.opacity(0.08),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                    .fill(effectiveThemeColor.opacity(0.08))
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.45 : 0.2),
                radius: 30,
                x: 0,
                y: 15
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
        withAnimation {
            isDeleted = true
            FeedbackManager.shared.trigger(.removeFromLibrary)
        }

        dismiss()

        Task {
            try? await Task.sleep(for: .seconds(0.5))
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
