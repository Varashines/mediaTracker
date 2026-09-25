import SwiftUI

/// Shared scaffolding for home-screen horizontal carousels: section header,
/// fast-scroll-aware `ScrollingHStack`, and per-item interactive buttons.
///
/// Scroll progress and horizontal fast-scroll live on `CarouselScrollState`
/// so progress ticks only invalidate the header child — not the card row.
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
    let card: (Item) -> Card

    @State private var scroll = CarouselScrollState()

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
        card: @escaping (Item) -> Card
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
        card: @escaping (Item) -> Card
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
            CarouselProgressHeader(
                title: title,
                icon: icon,
                iconColor: iconColor,
                state: showsScrollProgress ? scroll : nil
            )

            if !items.isEmpty {
                ScrollingHStack(space: scrollSpace, spacing: spacing, state: scroll) {
                    ForEach(items) { item in
                        if let onSelect {
                            Button { onSelect(item) } label: {
                                card(item)
                                    .equatable()
                            }
                            .buttonStyle(.interactive)
                        } else {
                            card(item)
                                .equatable()
                        }
                    }
                }
                .fastScrollingEnvironment(state: scroll)
            } else if let emptyContent {
                emptyContent()
            }
        }
    }
}

/// Isolates `scroll.progress` reads so progress ticks do not re-run the
/// parent section body (and its `ForEach`).
private struct CarouselProgressHeader: View {
    let title: String
    let icon: String
    let iconColor: Color
    /// Non-nil when the progress indicator should show.
    let state: CarouselScrollState?

    var body: some View {
        SectionHeader(
            title: title,
            icon: icon,
            iconColor: iconColor,
            scrollProgress: state?.progress
        )
    }
}
