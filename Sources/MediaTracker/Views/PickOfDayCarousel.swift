import SwiftUI

struct PickOfDayCarousel: View {
    let items: [MediaThumbnailMetadata]
    let namespace: Namespace.ID
    let onSelect: (MediaThumbnailMetadata) -> Void

    var body: some View {
        HomeCarouselSection(
            title: "Pick of the Day",
            icon: "star.fill",
            iconColor: .yellow,
            scrollSpace: "POD_Scroll",
            items: items,
            spacing: AppTheme.Spacing.smallMedium,
            onSelect: onSelect
        ) { metadata in
            ForYouCompactCard(metadata: metadata)
        }
    }
}
