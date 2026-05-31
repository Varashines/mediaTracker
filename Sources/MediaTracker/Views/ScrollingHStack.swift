import SwiftUI

struct ScrollingHStack<Content: View>: View {
    let space: String
    @Binding var scrollProgress: Double
    @ViewBuilder let content: () -> Content

    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: AppTheme.Spacing.large) {
                content()
            }
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
            .padding(.vertical, AppTheme.Spacing.medium - 1)
            .background(
                GeometryReader { geo in
                    let minX = geo.frame(in: .named(space)).minX
                    Color.clear
                        .preference(key: ScrollOffsetKey.self, value: [space: minX])
                        .onAppear { contentWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, nv in contentWidth = nv }
                }
            )
        }
        .scrollBounceBehavior(.basedOnSize)
        .coordinateSpace(name: space)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, nv in containerWidth = nv }
            }
        )
        .onPreferenceChange(ScrollOffsetKey.self) { dict in
            guard let minX = dict[space] else { return }
            let maxScroll = max(1, contentWidth - containerWidth)
            let newProgress = min(1.0, Double(max(0, -minX) / maxScroll))
            if newProgress == 0.0 || newProgress == 1.0 || abs(scrollProgress - newProgress) > 0.015 {
                scrollProgress = newProgress
            }
        }
        .scrollClipDisabled()
    }
}
