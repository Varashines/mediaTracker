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
                title: "Coming Soon",
                icon: "sparkles",
                iconColor: .yellow,
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
                    GeometryReader { (geo: GeometryProxy) in
                        let minX: CGFloat = geo.frame(in: .named(scrollSpace)).minX
                        Color.clear
                            .preference(key: ScrollOffsetKey.self, value: [scrollSpace: minX])
                            .onAppear { contentWidth = geo.size.width }
                            .onChange(of: geo.size.width) { (_: CGFloat, newValue: CGFloat) in contentWidth = newValue }
                    }
                )
            }
            .scrollBounceBehavior(.basedOnSize)
            .coordinateSpace(name: scrollSpace)
            .background(
                GeometryReader { (geo: GeometryProxy) in
                    Color.clear
                        .onAppear { containerWidth = geo.size.width }
                        .onChange(of: geo.size.width) { (_: CGFloat, newValue: CGFloat) in containerWidth = newValue }
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { (dict: [String: CGFloat]) in
                guard let minX = dict[scrollSpace] else { return }
                let maxScroll = max(1, contentWidth - containerWidth)
                let currentScroll = max(0, -minX)
                scrollProgress = min(1.0, currentScroll / maxScroll)
            }
        }
        .compositingGroup()
        .onAppear { prewarm(items: items) }
        .onChange(of: items) { _, newItems in prewarm(items: newItems) }
    }

    private func prewarm(items: [MediaThumbnailMetadata]) {
        let urls = items.prefix(10).compactMap { $0.posterURL }.compactMap { URL(string: $0) }
        if !urls.isEmpty {
            ImageCache.shared.prewarmImages(urls: urls, targetSize: .thumbMedium, priority: .normal)
        }
    }
}
