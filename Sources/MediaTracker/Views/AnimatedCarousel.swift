import SwiftUI

/// Generic horizontal carousel with the standard fade-in reveal pattern used by
/// `CastSectionView` and `RecommendationSectionView`. Centralizes the `isVisible`
/// state, the `LazyHStack` layout, and the `scrollBounceBehavior` so both call
/// sites stay in sync.
struct AnimatedCarousel<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let spacing: CGFloat
    @ViewBuilder let content: (Item) -> Content

    @State private var isVisible = false

    init(items: [Item], spacing: CGFloat = 16, @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: spacing) {
                ForEach(items) { item in
                    content(item)
                        .offset(x: isVisible ? 0 : 20)
                        .opacity(isVisible ? 1 : 0)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            withAnimation(AppTheme.Animation.easeInOut) {
                isVisible = true
            }
        }
    }
}
