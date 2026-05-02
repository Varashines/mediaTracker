import SwiftUI
import SwiftData

struct ContinueWatchingCarousel: View {
    let items: [MediaThumbnailMetadata]
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let onSelect: (MediaThumbnailMetadata) -> Void
    
    @State private var scrollProgress: Double = 0
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    private let scrollSpace = "CW_Scroll"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Continue Watching", 
                icon: "play.fill", 
                iconColor: .blue,
                scrollProgress: items.count > 1 ? scrollProgress : nil
            )
            
            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        Spacer(minLength: 10)
                        ForEach(items) { metadata in
                            Button { onSelect(metadata) } label: {
                                MediaThumbnailView(metadata: metadata, mode: .hero, namespace: namespace, isFastScrolling: isFastScrolling)
                            }
                            .buttonStyle(.interactive)
                        }
                        Spacer(minLength: 10)
                    }
                    .padding(.vertical, 15)
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
                    withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                        scrollProgress = min(1.0, currentScroll / maxScroll)
                    }
                }
                .scrollClipDisabled()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(0..<6, id: \.self) { _ in
                            MediaThumbnailPlaceholder(mode: .hero)
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 15)
                }
                .scrollClipDisabled()
            }
        }
    }
}
