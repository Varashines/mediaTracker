import SwiftUI

/// Shared scaffolding for home-screen horizontal carousels: section header,
/// fast-scroll-aware `ScrollingHStack`, and per-item interactive buttons.
///
/// Consolidates what used to be copy-pasted across FeaturedUpcomingCarousel,
/// PickOfDayCarousel, ForYouCarousel, and ContinueWatchingCarousel.
struct HomeCarouselSection<Item: Identifiable, Card: Equatable & View, EmptyContent: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    /// Unique preference-key namespace for this carousel's scroll tracking.
    let scrollSpace: String
    let items: [Item]
    /// Pass `false` to hide the header's scroll-progress indicator (e.g. single-item rows).
    let showsScrollProgress: Bool
    /// Inter-card spacing. Defaults to the shared row gap; denser rows
    /// (e.g. Apple TV-style landscape cards) pass something tighter.
    let spacing: CGFloat
    /// When set, each card is wrapped in an interactive `Button`.
    let onSelect: ((Item) -> Void)?
    let emptyContent: (() -> EmptyContent)?
    let card: (Item, _ isFastScrolling: Bool) -> Card

    @State private var scrollProgress: Double = 0
    @State private var horizontalFastScrolling = false

    init(
        title: String,
        icon: String,
        iconColor: Color,
        scrollSpace: String,
        items: [Item],
        showsScrollProgress: Bool = true,
        spacing: CGFloat = AppTheme.Spacing.large,
        onSelect: ((Item) -> Void)? = nil,
        @ViewBuilder emptyContent: @escaping () -> EmptyContent,
        card: @escaping (Item, _ isFastScrolling: Bool) -> Card
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.scrollSpace = scrollSpace
        self.items = items
        self.showsScrollProgress = showsScrollProgress
        self.spacing = spacing
        self.onSelect = onSelect
        self.emptyContent = emptyContent
        self.card = card
    }

    init(
        title: String,
        icon: String,
        iconColor: Color,
        scrollSpace: String,
        items: [Item],
        showsScrollProgress: Bool = true,
        spacing: CGFloat = AppTheme.Spacing.large,
        onSelect: ((Item) -> Void)? = nil,
        card: @escaping (Item, _ isFastScrolling: Bool) -> Card
    ) where EmptyContent == EmptyView {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.scrollSpace = scrollSpace
        self.items = items
        self.showsScrollProgress = showsScrollProgress
        self.spacing = spacing
        self.onSelect = onSelect
        self.emptyContent = nil
        self.card = card
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            SectionHeader(
                title: title,
                icon: icon,
                iconColor: iconColor,
                scrollProgress: showsScrollProgress ? scrollProgress : nil
            )

            if !items.isEmpty {
                ScrollingHStack(space: scrollSpace, spacing: spacing, scrollProgress: $scrollProgress, isFastScrolling: $horizontalFastScrolling) {
                    ForEach(items) { item in
                        if let onSelect {
                            Button { onSelect(item) } label: {
                                card(item, horizontalFastScrolling)
                                    .equatable()
                                    .compositingGroupIfNeeded()
                            }
                            .buttonStyle(.interactive)
                        } else {
                            card(item, horizontalFastScrolling)
                                .equatable()
                                .compositingGroupIfNeeded()
                        }
                    }
                }
            } else if let emptyContent {
                emptyContent()
            }
        }
    }
}
