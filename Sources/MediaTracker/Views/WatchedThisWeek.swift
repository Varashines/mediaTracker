import SwiftUI
import SwiftData

private enum WatchFilter: String, CaseIterable {
    case all
    case movies
    case shows

    var title: String {
        switch self {
        case .all: return "All"
        case .movies: return "Movies"
        case .shows: return "TV Shows"
        }
    }

    var icon: String {
        switch self {
        case .all: return "rectangle.stack.fill"
        case .movies: return "film.fill"
        case .shows: return "tv.fill"
        }
    }
}

struct WatchedThisWeek: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var movieItems: [MediaItem] = []
    @State private var showItems: [MediaItem] = []
    @State private var watchDates: [PersistentIdentifier: Date] = [:]
    @State private var isLoading = true
    @State private var filter: WatchFilter = .all
    @State private var hoveredPill: WatchFilter? = nil
    @State private var scroll = CarouselScrollState()
    @State private var refreshCoalesceTask: Task<Void, Never>?
    @Namespace private var filterAnimation
    private let scrollSpace = "WTW_Scroll"

    private var filteredItems: [MediaItem] {
        switch filter {
        case .all:
            return (movieItems + showItems).sorted {
                (watchDates[$0.persistentModelID] ?? .distantPast) > (watchDates[$1.persistentModelID] ?? .distantPast)
            }
        case .movies:
            return movieItems
        case .shows:
            return showItems
        }
    }

    private var filteredEmptyMessage: String {
        switch filter {
        case .all: return "Nothing watched this week"
        case .movies: return "No movies watched this week"
        case .shows: return "No TV shows watched this week"
        }
    }

    var body: some View {
        // Computed once per body eval — the .all case concatenates and sorts
        // live model arrays, and this was previously evaluated in both the
        // emptiness check below and the ForEach.
        let items = filteredItems

        return VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            WatchedThisWeekHeader(
                scroll: scroll,
                filter: filter,
                filterPills: AnyView(filterPills)
            )

            if isLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: AppTheme.Spacing.large) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                                .fill(AppTheme.Colors.surfaceSubtle(for: colorScheme))
                                .overlay {
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                                        .stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 1)
                                }
                                .frame(width: AppTheme.Thumbnail.small.width, height: AppTheme.Thumbnail.small.height)
                        }
                    }
                    .shimmering()
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .padding(.vertical, AppTheme.Spacing.medium - 1)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else if movieItems.isEmpty && showItems.isEmpty {
                HStack(spacing: AppTheme.Spacing.small) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(AppTheme.Font.title3)
                        .foregroundStyle(Color.semanticGreen(for: colorScheme).opacity(0.5))
                    Text("Nothing watched this week")
                        .font(AppTheme.Font.body)
                        .foregroundStyle(.tertiary)
                }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, AppTheme.Spacing.small)
                } else if items.isEmpty {
                HStack(spacing: AppTheme.Spacing.small) {
                    Image(systemName: filter.icon)
                        .font(AppTheme.Font.title3)
                        .foregroundStyle(Color.semanticGreen(for: colorScheme).opacity(0.4))
                    Text(filteredEmptyMessage)
                        .font(AppTheme.Font.body)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, AppTheme.Spacing.small)
                .transition(.mediaRowArrival)
            } else {
                ScrollingHStack(space: scrollSpace, state: scroll) {
                    ForEach(items, id: \.persistentModelID) { item in
                        NavigationLink(value: item) {
                            MediaThumbnailView(
                                item: item,
                                mode: .grid,
                                showTypeBadge: true
                            )
                            .equatable()
                            .frame(width: 160)
                        }
                        .buttonStyle(.interactive)
                    }
                }
                .fastScrollingEnvironment(state: scroll)
                .id(filter)
                .transition(.mediaRowArrival)
            }
        }
        .task { await fetchRecentItems() }
        .onDisappear {
            refreshCoalesceTask?.cancel()
            refreshCoalesceTask = nil
        }
        .animation(AppTheme.Animation.easeInOut, value: filter)
        // Leaf observer: counter ticks must not re-eval this row body.
        .background {
            MediaStateLeafObserver(
                onSingleItemUpdate: { _ in scheduleCoalescedRecentRefresh() },
                onFullRefresh: { scheduleCoalescedRecentRefresh() }
            )
        }
    }

    /// Coalesce undebounced single-item ticks + full-refresh ticks into one
    /// pool refetch (binge marks were firing two expanding scans per episode).
    private func scheduleCoalescedRecentRefresh() {
        refreshCoalesceTask?.cancel()
        refreshCoalesceTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await fetchRecentItems()
        }
    }

    private func fetchRecentItems() async {
        let container = modelContext.container
        let (movies, shows) = await Task.detached(priority: .userInitiated) { () -> ([WatchActivityCandidate], [WatchActivityCandidate]) in
            let backgroundContext = ModelContext(container)
            let candidates = WatchActivityResolver.candidates(
                types: [.movie, .tvShow],
                context: backgroundContext
            )
            return (
                Self.fetchPool(type: .movie, candidates: candidates),
                Self.fetchPool(type: .tvShow, candidates: candidates)
            )
        }.value

        movieItems = movies.compactMap { modelContext.model(for: $0.id) as? MediaItem }
        showItems = shows.compactMap { modelContext.model(for: $0.id) as? MediaItem }
        watchDates = Dictionary(uniqueKeysWithValues: (movies + shows).map { ($0.id, $0.watchedAt) })
        withAnimation(AppTheme.Animation.easeInOut) { isLoading = false }
    }

    /// Watched this week; if fewer than `minCount` of a type, expand the window until we have 10.
    nonisolated private static func fetchPool(
        type: MediaType,
        candidates: [WatchActivityCandidate]
    ) -> [WatchActivityCandidate] {
        let minCount = 10
        let weekCap = 30
        let fillWindows: [TimeInterval] = [.days14, .days30]
        let candidates = candidates.filter { $0.type == type }

        // Phase 1 — strict "watched this week", no filling. Show the whole week.
        let week = WatchActivityResolver.recentCandidates(
            candidates: candidates,
            cutoff: Date(timeIntervalSinceNow: -.days7),
            limit: weekCap
        )
        if week.count >= minCount { return week }

        // Phase 2 — <10 this week → pull the last 10 from older history.
        var best = week
        for window in fillWindows {
            let results = WatchActivityResolver.recentCandidates(
                candidates: candidates,
                cutoff: Date(timeIntervalSinceNow: -window),
                limit: minCount
            )
            best = results
            if results.count >= minCount { return results }
        }
        let allTime = WatchActivityResolver.recentCandidates(
            candidates: candidates,
            cutoff: .distantPast,
            limit: minCount
        )
        return allTime.count >= best.count ? allTime : best
    }

    private var filterPills: some View {
        HStack(spacing: 2) {
            ForEach(WatchFilter.allCases, id: \.self) { option in
                filterPill(option)
            }
        }
        .padding(3)
        .background {
            Capsule().fill(AppTheme.Colors.cardFill(for: colorScheme))
        }
        .overlay {
            Capsule().stroke(
                AppTheme.Colors.strokeDefault(for: colorScheme),
                lineWidth: 0.5
            )
        }
    }

    private func filterPill(_ option: WatchFilter) -> some View {
        let isSelected = filter == option
        let isHovered = hoveredPill == option
        return Button {
            withAnimation(AppTheme.Animation.springSnappy) {
                filter = option
            }
            scroll.progress = 0
            FeedbackManager.shared.trigger(.click)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: option.icon)
                    .font(AppTheme.Font.caption2)
                Text(option.title)
                    .font(AppTheme.Font.caption2)
            }
            .foregroundStyle(isSelected ? AppTheme.Colors.accent.readableForeground : (isHovered ? Color.primary : Color.secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if isSelected {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.Colors.accent, AppTheme.Colors.accent.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .matchedGeometryEffect(id: "activeFilterPill", in: filterAnimation)
                        .shadow(color: AppTheme.Colors.accent.opacity(0.35), radius: 4, y: 1)
                }
            }
            .overlay {
                if isSelected {
                    Capsule()
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                        .matchedGeometryEffect(id: "activeFilterPillStroke", in: filterAnimation)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.springSnappy) {
                hoveredPill = hovering ? option : nil
            }
        }
        .help(option.title)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Reads `scroll.progress` in isolation so preference ticks don't re-run
/// WatchedThisWeek's body (fetch, filter lists, card ForEach).
private struct WatchedThisWeekHeader: View {
    let scroll: CarouselScrollState
    let filter: WatchFilter
    let filterPills: AnyView

    var body: some View {
        SectionHeader(
            title: "Recently Watched",
            icon: "clock.fill",
            iconColor: .green,
            scrollProgress: scroll.progress,
            trailingAccessory: { filterPills }
        )
    }
}
