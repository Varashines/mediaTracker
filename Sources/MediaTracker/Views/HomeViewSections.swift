import SwiftUI
import SwiftData

struct HomeViewSections: View {
    let homeContinueWatching: [MediaThumbnailMetadata]
    let featuredCarouselItems: [MediaThumbnailMetadata]
    let groupedItems: [(String, [MediaThumbnailMetadata])]
    let recentlyAdded: [MediaThumbnailMetadata]
    let recommendations: [MediaThumbnailMetadata]
    /// True once a recommendations fetch has settled (even empty).
    let recommendationsLoaded: Bool
    let pickOfTheDay: [MediaThumbnailMetadata]
    let trendingMovies: [MediaSearchResult]
    let trendingShows: [MediaSearchResult]
    let namespace: Namespace.ID
    @Environment(\.isFastScrolling) private var isFastScrolling
    let onSelectHero: (MediaThumbnailMetadata) -> Void
    let onCategorySelected: (NavigationCategory) -> Void
    let onTrendingAdd: ((MediaSearchResult) -> Void)?
    var onFetchRecommendations: (() -> Void)? = nil
    var onFetchPickOfTheDay: (() -> Void)? = nil
    var onFetchTrending: (() -> Void)? = nil

    private enum HomeSection {
        case forYou, recentlyWatched, pickOfTheDay, trendingMovies, trendingShows
    }

    @State private var visibleSection: HomeSection? = nil
    @State private var activePillAnchor: CGRect?
    private static let focusCoordinateSpace = "homeFocusSurface"

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            SectionPicker(
                visibleSection: $visibleSection,
                activePillAnchor: $activePillAnchor,
                coordinateSpace: Self.focusCoordinateSpace,
                showsPickOfTheDay: !pickOfTheDay.isEmpty
            )
            .padding(.horizontal, AppTheme.Spacing.pageMargin)

            if visibleSection != nil {
                selectedSectionContent
                    .padding(.vertical, AppTheme.Spacing.medium)
                    .background {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                            .fill(AppTheme.Colors.accent.opacity(0.07))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                            .stroke(AppTheme.Colors.accent.opacity(0.16), lineWidth: 0.5)
                    }
                    .overlay {
                        GeometryReader { proxy in
                            if let activePillAnchor {
                                focusConnector(in: proxy, anchor: activePillAnchor)
                                    .animation(AppTheme.Animation.adaptive(AppTheme.Animation.springSnappy), value: activePillAnchor)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.large)
                    .transition(.opacity)
            }

            // 1. CONTINUE WATCHING
            ContinueWatchingCarousel(
                items: homeContinueWatching, namespace: namespace,
                onSelect: onSelectHero
            ) {
                onCategorySelected(.discover)
            }
            .padding(.vertical, AppTheme.Spacing.small)

            // 2. COMING SOON (Limited to 20)
            let comingSoon = featuredCarouselItems.isEmpty ? (groupedItems.first(where: { $0.0 == "Coming Soon" })?.1 ?? []) : featuredCarouselItems
            if !comingSoon.isEmpty {
                FeaturedUpcomingCarousel(
                    items: Array(comingSoon.prefix(20)), namespace: namespace,
                    onSelect: onSelectHero
                )
                .padding(.bottom, AppTheme.Spacing.small)
            }

            // 3. RECENTLY ADDED — permanent portrait row, same .grid card
            // size as Coming Soon.
            if !recentlyAdded.isEmpty {
                HomeCarouselSection(
                    title: "Recently Added",
                    icon: "clock.badge.checkmark",
                    iconColor: .orange,
                    scrollSpace: "RA_Scroll",
                    items: Array(recentlyAdded.prefix(20)),
                    onSelect: onSelectHero
                ) { metadata in
                    MediaThumbnailView(
                        metadata: metadata, mode: .grid,
                        namespace: namespace)
                }
                .padding(.bottom, AppTheme.Spacing.small)
            }
        }
        .coordinateSpace(name: Self.focusCoordinateSpace)
        .padding(.top, AppTheme.Spacing.medium)
    }

    private func focusConnector(in proxy: GeometryProxy, anchor: CGRect) -> some View {
        let surfaceFrame = proxy.frame(in: .named(Self.focusCoordinateSpace))
        let rawX = anchor.midX - surfaceFrame.minX
        let x = min(max(rawX, 14), max(14, proxy.size.width - 14))

        return ZStack(alignment: .top) {
            Rectangle()
                .fill(AppTheme.Colors.accent.opacity(0.5))
                .frame(width: 3, height: 8)
                .offset(x: x - 1.5, y: -4)

            Path { path in
                path.move(to: CGPoint(x: x - 8, y: 0))
                path.addLine(to: CGPoint(x: x + 8, y: 0))
                path.addLine(to: CGPoint(x: x, y: 9))
                path.closeSubpath()
            }
            .fill(AppTheme.Colors.accent.opacity(0.16))
        }
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        if visibleSection == .recentlyWatched {
            WatchedThisWeek()
        }

        if visibleSection == .forYou {
            ForYouCarousel(
                items: recommendations, namespace: namespace,
                onSelect: onSelectHero,
                isLoading: !recommendationsLoaded,
                onDiscover: { onCategorySelected(.discover) }
            )
            .onAppear {
                if recommendations.isEmpty && !recommendationsLoaded {
                    onFetchRecommendations?()
                }
            }
        }

        if visibleSection == .pickOfTheDay {
            PickOfDayCarousel(
                items: pickOfTheDay, namespace: namespace,
                onSelect: onSelectHero
            )
            .onAppear {
                if pickOfTheDay.isEmpty {
                    onFetchPickOfTheDay?()
                }
            }
        }

        if visibleSection == .trendingMovies {
            TrendingCarousel(items: trendingMovies, title: "Trending Movies") { result in
                onTrendingAdd?(result)
            }
            .onAppear {
                if trendingMovies.isEmpty {
                    onFetchTrending?()
                }
            }
        }

        if visibleSection == .trendingShows {
            TrendingCarousel(items: trendingShows, title: "Trending Shows") { result in
                onTrendingAdd?(result)
            }
            .onAppear {
                if trendingShows.isEmpty {
                    onFetchTrending?()
                }
            }
        }
    }

    private struct SectionPicker: View {
        @Binding var visibleSection: HomeSection?
        @Binding var activePillAnchor: CGRect?
        let coordinateSpace: String
        let showsPickOfTheDay: Bool
        @State private var hoveredPill: HomeSection?
        @Namespace private var pillNamespace
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            ViewThatFits(in: .horizontal) {
                sectionButtons
                    .frame(maxWidth: .infinity)

                ScrollView(.horizontal, showsIndicators: false) {
                    sectionButtons
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }

        @ViewBuilder
        private var sectionButtons: some View {
            HStack(spacing: AppTheme.Spacing.tiny) {
                Spacer(minLength: 0)
                sectionButton(
                    section: .forYou,
                    icon: "sparkles",
                    label: "For You",
                    isActive: visibleSection == .forYou
                )
                sectionButton(
                    section: .recentlyWatched,
                    icon: "clock.fill",
                    label: "Recently Watched",
                    isActive: visibleSection == .recentlyWatched
                )
                if showsPickOfTheDay {
                    sectionButton(
                        section: .pickOfTheDay,
                        icon: "star.fill",
                        label: "Pick of the Day",
                        isActive: visibleSection == .pickOfTheDay
                    )
                }
                sectionButton(
                    section: .trendingMovies,
                    icon: "flame.fill",
                    label: "Trending Movies",
                    isActive: visibleSection == .trendingMovies
                )
                sectionButton(
                    section: .trendingShows,
                    icon: "flame.fill",
                    label: "Trending Shows",
                    isActive: visibleSection == .trendingShows
                )
                Spacer(minLength: 0)
            }
        }

        private func reportPillFrame(_ frame: CGRect, isActive: Bool) {
            guard isActive, activePillAnchor != frame else { return }
            activePillAnchor = frame
        }

        private func sectionButton(section: HomeSection, icon: String, label: String, isActive: Bool) -> some View {
            Button {
                AppTheme.Animation.with(AppTheme.Animation.springSnappy) {
                    if visibleSection == section {
                        visibleSection = nil
                    } else {
                        visibleSection = section
                    }
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.mini) {
                    Image(systemName: icon)
                        .font(AppTheme.Font.caption2)
                    Text(label)
                        .font(AppTheme.Font.caption)
                }
                .padding(.horizontal, AppTheme.Spacing.small)
                .padding(.vertical, AppTheme.Spacing.mini)
                 .background {
                     Capsule()
                         .fill(isActive ? AppTheme.Colors.accent : (hoveredPill == section ? AppTheme.Colors.surfaceMuted(for: scheme) : AppTheme.Colors.surfaceSubtle(for: scheme)))
                         .overlay {
                             if isActive {
                                 Capsule()
                                     .fill(AppTheme.Colors.accent)
                                     .matchedGeometryEffect(id: "homePill", in: pillNamespace)
                             }
                         }
                 }
                 .background {
                     GeometryReader { proxy in
                         let frame = proxy.frame(in: .named(coordinateSpace))
                         Color.clear
                             .onAppear { reportPillFrame(frame, isActive: isActive) }
                             .onChange(of: frame) { _, newFrame in
                                 reportPillFrame(newFrame, isActive: isActive)
                             }
                             .onChange(of: isActive) { _, active in
                                 if active {
                                     reportPillFrame(proxy.frame(in: .named(coordinateSpace)), isActive: true)
                                 }
                             }
                     }
                 }
                 .shadow(color: isActive ? AppTheme.Colors.accent.opacity(0.25) : .clear, radius: 4, y: 2)
                .foregroundStyle(isActive ? AppTheme.Colors.accent.readableForeground : .primary)
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .scaleEffect(!isActive && hoveredPill == section ? 1.03 : 1.0)
            .animation(AppTheme.Animation.springSnappy, value: hoveredPill)
            .onHover { hovering in
                withAnimation(AppTheme.Animation.springSnappy) {
                    hoveredPill = hovering ? section : nil
                }
            }
            .accessibilityLabel(label)
            .accessibilityAddTraits(isActive ? .isSelected : [])
        }
    }
}
