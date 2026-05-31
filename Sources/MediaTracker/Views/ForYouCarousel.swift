import SwiftUI
import SwiftData

struct ForYouCarousel: View {
    let items: [MediaThumbnailMetadata]
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let onSelect: (MediaThumbnailMetadata) -> Void
    
    @State private var scrollProgress: Double = 0
    private let scrollSpace = "FY_Scroll"

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            SectionHeader(
                title: "For You", 
                icon: "sparkles", 
                iconColor: .yellow,
                scrollProgress: scrollProgress
            )

            if !items.isEmpty {
                ScrollingHStack(space: scrollSpace, scrollProgress: $scrollProgress) {
                    ForEach(items) { metadata in
                        Button { onSelect(metadata) } label: {
                            ForYouCompactCard(metadata: metadata, namespace: namespace, isFastScrolling: isFastScrolling)
                        }
                        .buttonStyle(.interactive)
                    }
                }
            }
        }
        .compositingGroup()
    }
}
