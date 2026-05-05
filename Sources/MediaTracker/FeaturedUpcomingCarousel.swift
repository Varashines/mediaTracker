import SwiftUI
import SwiftData

struct FeaturedUpcomingCarousel: View {
    let items: [MediaThumbnailMetadata]
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let onSelect: (MediaThumbnailMetadata) -> Void
    
    @State private var scrollProgress: Double = 0
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    private let scrollSpace = "Featured_Scroll"

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(
                title: "Featured",
                icon: nil,
                iconColor: .secondary,
                scrollProgress: scrollProgress
            )
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(items) { metadata in
                        Button { onSelect(metadata) } label: {
                            MediaThumbnailView(metadata: metadata, mode: .hero, isUpcomingSection: true, namespace: namespace, isFastScrolling: isFastScrolling)
                                .id(metadata.versionHash)
                        }
                        .buttonStyle(.interactive)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 20)
                .background(
                    GeometryReader { geo in
                        let minX = geo.frame(in: .named(scrollSpace)).minX
                        Color.clear
                            .preference(key: ScrollOffsetKey.self, value: [scrollSpace: minX])
                            .onAppear { contentWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, newValue in contentWidth = newValue }
                    }
                )
            }
            .coordinateSpace(name: scrollSpace)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { containerWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, newValue in containerWidth = newValue }
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { dict in
                guard let minX = dict[scrollSpace] else { return }
                let maxScroll = max(1, contentWidth - containerWidth)
                let currentScroll = max(0, -minX)
                withAnimation(.smooth) {
                    scrollProgress = min(1.0, currentScroll / maxScroll)
                }
            }
        }
        .compositingGroup()
    }
}
