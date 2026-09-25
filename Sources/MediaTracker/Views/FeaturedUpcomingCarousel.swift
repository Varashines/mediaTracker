import SwiftUI
import SwiftData

struct FeaturedUpcomingCarousel: View {
    let items: [MediaThumbnailMetadata]
    let namespace: Namespace.ID
    let onSelect: (MediaThumbnailMetadata) -> Void

    var body: some View {
        HomeCarouselSection(
            title: "Coming Soon",
            icon: "sparkles",
            iconColor: .yellow,
            scrollSpace: "Featured_Scroll",
            items: items,
            onSelect: onSelect
        ) { metadata in
            MediaThumbnailView(
                metadata: metadata, mode: .grid, isUpcomingSection: true,
                namespace: namespace)
        }
        .scrollClipDisabled()
    }
}
