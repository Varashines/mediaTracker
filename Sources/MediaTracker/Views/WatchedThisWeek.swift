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
    @State private var isLoading = true
    @State private var filter: WatchFilter = .all
    @State private var hoveredPill: WatchFilter? = nil
    @State private var scrollProgress: Double = 0
    @State private var horizontalFastScrolling = false
    @Namespace private var filterAnimation
    private let scrollSpace = "WTW_Scroll"

    private let minCount = 10
    private let weekCap = 30
    private let fillWindows: [TimeInterval] = [.days14, .days30]

    private var filteredItems: [MediaItem] {
        switch filter {
        case .all:
            return (movieItems + showItems).sorted {
                ($0.lastInteractionDate ?? .distantPast) > ($1.lastInteractionDate ?? .distantPast)
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            SectionHeader(
                title: "Watched This Week",
                icon: "clock.fill",
                iconColor: .green,
                scrollProgress: scrollProgress,
                trailingAccessory: { AnyView(filterPills) }
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
                                .shimmering()
                        }
                    }
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
                .transition(.mediaRowArrival)
            } else if filteredItems.isEmpty {
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
                ScrollingHStack(space: scrollSpace, scrollProgress: $scrollProgress, isFastScrolling: $horizontalFastScrolling) {
                    ForEach(filteredItems, id: \.persistentModelID) { item in
                        NavigationLink(value: item) {
                            MediaThumbnailView(
                                item: item,
                                mode: .grid,
                                showTypeBadge: true,
                                isFastScrolling: horizontalFastScrolling
                            )
                            .equatable()
                            .compositingGroupIfNeeded()
                            .frame(width: 160)
                        }
                        .buttonStyle(.interactive)
                    }
                }
                .id(filter)
                .transition(.mediaRowArrival)
            }
        }
        .task { fetchRecentItems() }
        .animation(AppTheme.Animation.easeInOut, value: filter)
    }

    private func fetchRecentItems() {
        movieItems = fetchPool(type: .movie)
        showItems = fetchPool(type: .tvShow)
        withAnimation(AppTheme.Animation.easeInOut) { isLoading = false }
    }

    /// Watched this week; if fewer than `minCount` of a type, expand the window until we have 10.
    private func fetchPool(type: MediaType) -> [MediaItem] {
        let raw = type.rawValue

        // Phase 1 — strict "watched this week", no filling. Show the whole week.
        let week = fetch(typeRaw: raw, cutoff: Date(timeIntervalSinceNow: -.days7), limit: weekCap)
        if week.count >= minCount { return week }

        // Phase 2 — <10 this week → pull the last 10 from older history.
        var best = week
        for window in fillWindows {
            let results = fetch(typeRaw: raw, cutoff: Date(timeIntervalSinceNow: -window), limit: minCount)
            best = results
            if results.count >= minCount { return results }
        }
        let allTime = fetch(typeRaw: raw, cutoff: .distantPast, limit: minCount)
        return allTime.count >= best.count ? allTime : best
    }

    private func fetch(typeRaw: String, cutoff: Date, limit: Int?) -> [MediaItem] {
        let predicate = #Predicate<MediaItem> {
            ($0.lastInteractionDate ?? cutoff) >= cutoff && $0.stateValue != "Wishlist" && $0.typeValue == typeRaw
        }
        var descriptor = FetchDescriptor<MediaItem>(predicate: predicate)
        descriptor.fetchLimit = limit
        descriptor.sortBy = [SortDescriptor(\.lastInteractionDate, order: .reverse)]
        descriptor.propertiesToFetch = MediaItem.thumbnailProperties
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private var filterPills: some View {
        HStack(spacing: 2) {
            ForEach(WatchFilter.allCases, id: \.self) { option in
                filterPill(option)
            }
        }
        .padding(3)
        .background {
            Capsule().fill(AppThemeCoordinator.isReducingVisualEffects
                ? AnyShapeStyle(AppTheme.Colors.cardFill(for: colorScheme))
                : AnyShapeStyle(.ultraThinMaterial))
        }
        .overlay {
            Capsule().stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.18), AppTheme.Colors.strokeDefault(for: colorScheme)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.5
            )
        }
        .if(!AppThemeCoordinator.isReducingVisualEffects) {
            $0.shadow(color: AppTheme.Colors.shadowAmbient(for: colorScheme), radius: 6, y: 2)
        }
    }

    private func filterPill(_ option: WatchFilter) -> some View {
        let isSelected = filter == option
        let isHovered = hoveredPill == option
        return Button {
            withAnimation(AppTheme.Animation.springSnappy) {
                filter = option
            }
            scrollProgress = 0
            FeedbackManager.shared.trigger(.click)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: option.icon)
                    .font(AppTheme.Font.caption2)
                Text(option.title)
                    .font(AppTheme.Font.caption2)
            }
            .foregroundStyle(isSelected ? (AppTheme.Colors.accent.isLightColor ? .black : .white) : (isHovered ? Color.primary : Color.secondary))
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
