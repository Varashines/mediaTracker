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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            SectionHeader(
                title: "For You", 
                icon: "sparkles", 
                iconColor: .yellow,
                scrollProgress: scrollProgress
            )
            
            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.large) {
                        ForEach(items) { metadata in
                            Button { onSelect(metadata) } label: {
                                ForYouCompactCard(metadata: metadata, namespace: namespace, isFastScrolling: isFastScrolling)
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
                                .onChange(of: geo.size.width) { _, newValue in contentWidth = newValue }
                        }
                    )
                }
                .scrollBounceBehavior(.basedOnSize)
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
                        scrollProgress = min(1.0, currentScroll / maxScroll)
                    }
                }
                .scrollClipDisabled()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.secondary.opacity(0.1))
                                .frame(width: 420, height: 200)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .padding(.vertical, 15)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollClipDisabled()
            }
        }
        .compositingGroup()
    }
}
