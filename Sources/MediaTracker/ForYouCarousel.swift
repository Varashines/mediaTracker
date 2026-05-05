import SwiftUI
import SwiftData

struct ForYouCarousel: View {
    let items: [MediaThumbnailMetadata]
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let onSelect: (MediaThumbnailMetadata) -> Void
    
    @State private var scrollProgress: Double = 0
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    private let scrollSpace = "FY_Scroll"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "For You", 
                icon: "sparkles", 
                iconColor: .yellow,
                scrollProgress: scrollProgress
            )
            
            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 24) {
                        Spacer(minLength: 16)
                        ForEach(items) { metadata in
                            Button { onSelect(metadata) } label: {
                                HomeHeroCard(metadata: metadata, namespace: namespace, isFastScrolling: isFastScrolling)
                            }
                            .buttonStyle(.interactive)
                        }
                        Spacer(minLength: 16)
                    }
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
                    if let minX = dict[scrollSpace] {
                        let maxScroll = max(1, contentWidth - containerWidth)
                        let currentScroll = max(0, -minX)
                        withAnimation(.smooth) {
                            scrollProgress = min(1.0, currentScroll / maxScroll)
                        }
                    }
                }
                .scrollClipDisabled()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 24) {
                        ForEach(0..<3, id: \.self) { _ in
                            HomeHeroCardPlaceholder()
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 20)
                }
                .scrollClipDisabled()
            }
        }
    }
}
