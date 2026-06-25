import SwiftUI

/// Generic horizontal carousel with a staggered fade-in reveal pattern.
/// Each item animates with a progressive delay so cards appear in sequence.
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
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    content(item)
                        .offset(x: isVisible ? 0 : 20)
                        .opacity(isVisible ? 1 : 0)
                        .animation(AppTheme.Animation.springGentle.delay(Double(index) * 0.05), value: isVisible)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.vertical, AppTheme.Spacing.small)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            isVisible = true
        }
    }
}
