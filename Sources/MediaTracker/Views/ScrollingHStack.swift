import SwiftUI

struct ScrollingHStack<Content: View>: View {
    let space: String
    var spacing: CGFloat = AppTheme.Spacing.large
    var state: CarouselScrollState
    @ViewBuilder let content: () -> Content

    @State private var lastMinX: CGFloat = 0
    @State private var lastTimestamp: Date = .distantPast
    @State private var scrollTask: Task<Void, Never>?

    private let velocityThreshold: CGFloat = 30
    /// Progress-bar updates only — higher threshold = fewer observation pings.
    private let progressDeltaThreshold: Double = 0.02

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: spacing) {
                content()
            }
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
            .padding(.vertical, AppTheme.Spacing.medium - 1)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Disable clip only while idle (cards can bleed slightly); during a
        // fast-scroll gesture clipping is cheaper than per-frame clip revalidation.
        .scrollClipDisabled(!state.isFastScrolling)
        .onScrollGeometryChange(for: ScrollGeometry.self) { geo in
            geo
        } action: { _, geo in
            let maxScroll = max(1, geo.contentSize.width - geo.containerSize.width)
            // contentOffset.x grows from 0 → positive as you scroll right.
            // (The old minX preference went negative — do not negate here.)
            let offsetX = geo.contentOffset.x
            let newProgress = min(1.0, Double(max(0, offsetX) / maxScroll))
            if newProgress == 0.0 || newProgress == 1.0 || abs(state.progress - newProgress) > progressDeltaThreshold {
                state.progress = newProgress
            }

            let now = Date()
            let dt = max(now.timeIntervalSince(lastTimestamp), 1.0 / 120.0)
            let velocity = abs(offsetX - lastMinX) / CGFloat(dt)
            lastMinX = offsetX
            lastTimestamp = now

            if velocity > velocityThreshold && !state.isFastScrolling {
                state.isFastScrolling = true
            }

            // Coalesce clear: one Task per gesture window; no animation on clear
            // (withAnimation on fast-scroll clear re-renders header + env children).
            scrollTask?.cancel()
            scrollTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                state.isFastScrolling = false
            }
        }
    }
}
