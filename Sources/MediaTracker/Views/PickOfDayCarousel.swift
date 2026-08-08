import SwiftUI

struct PickOfDayCarousel: View {
    let items: [MediaThumbnailMetadata]
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let onSelect: (MediaThumbnailMetadata) -> Void

    @State private var scrollProgress: Double = 0
    @State private var horizontalFastScrolling = false
    private let scrollSpace = "POD_Scroll"

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            SectionHeader(
                title: "Pick of the Day",
                icon: "star.fill",
                iconColor: .yellow,
                scrollProgress: scrollProgress
            )

            if !items.isEmpty {
                ScrollingHStack(space: scrollSpace, scrollProgress: $scrollProgress, isFastScrolling: $horizontalFastScrolling) {
                    ForEach(items) { metadata in
                        Button { onSelect(metadata) } label: {
                            ForYouCompactCard(metadata: metadata, namespace: namespace, isFastScrolling: isFastScrolling || horizontalFastScrolling)
                                .equatable()
                                .compositingGroupIfNeeded()
                        }
                        .buttonStyle(.interactive)
                    }
                }
            }
        }
    }
}
