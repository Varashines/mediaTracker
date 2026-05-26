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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            SectionHeader(
                title: "Coming Soon",
                icon: "sparkles",
                iconColor: .yellow,
                scrollProgress: scrollProgress
            )
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: AppTheme.Spacing.large) {
                    ForEach(items) { metadata in
                        Button { onSelect(metadata) } label: {
                            MediaThumbnailView(metadata: metadata, mode: .hero, isUpcomingSection: true, namespace: namespace, isFastScrolling: isFastScrolling)
                                .id(metadata.versionHash)
                        }
                        .buttonStyle(.interactive)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.vertical, AppTheme.Spacing.medium - 1)
                .background(
                    GeometryReader { geo in
                         let minX = geo.frame(in: .named(scrollSpace)).minX
                        Color.clear
                            .preference(key: ScrollOffsetKey.self, value: [scrollSpace: minX])
                            .onAppear { contentWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, nv in contentWidth = nv }
                    }
                )
            }
            .scrollBounceBehavior(.basedOnSize)
            .coordinateSpace(name: scrollSpace)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { containerWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, nv in containerWidth = nv }
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { dict in
                guard let minX = dict[scrollSpace] else { return }
                let maxScroll = max(1, contentWidth - containerWidth)
                let newProgress = min(1.0, Double(max(0, -minX) / maxScroll))
                if newProgress == 0.0 || newProgress == 1.0 || abs(scrollProgress - newProgress) > 0.015 {
                    scrollProgress = newProgress
                }
            }
        }
        .scrollClipDisabled()
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
