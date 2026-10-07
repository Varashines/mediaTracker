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

    @State private var isHoveringRow = false
    @State private var scrollPosition = ScrollPosition(edge: .leading)

    var body: some View {
        ZStack {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: spacing) {
                    content()
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.vertical, AppTheme.Spacing.medium - 1)
            }
            .scrollPosition($scrollPosition)
            .scrollBounceBehavior(.basedOnSize)
            // Disable clip only while idle (cards can bleed slightly); during a
            // fast-scroll gesture clipping is cheaper than per-frame clip revalidation.
            .scrollClipDisabled(!state.isFastScrolling)

            // Mouse Scroll Assist Chevrons: subtle floating arrows on hover
            if isHoveringRow {
                HStack {
                    if state.progress > 0.02 {
                        carouselScrollArrow(direction: .left) {
                            withAnimation(AppTheme.Animation.springSnappy) {
                                scrollBy(delta: -480)
                            }
                        }
                    }
                    Spacer()
                    if state.progress < 0.98 {
                        carouselScrollArrow(direction: .right) {
                            withAnimation(AppTheme.Animation.springSnappy) {
                                scrollBy(delta: 480)
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.small)
                .transition(.opacity)
            }
        }
        .onHover { isHoveringRow = $0 }
        .onScrollGeometryChange(for: ScrollGeometry.self) { geo in
            geo
        } action: { _, geo in
            let maxScroll = max(1, geo.contentSize.width - geo.containerSize.width)
            // contentOffset.x grows from 0 → positive as you scroll right.
            // (The old minX preference went negative — do not negate here.)
            let offsetX = geo.contentOffset.x
            currentOffsetX = offsetX
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

    @State private var currentOffsetX: CGFloat = 0

    private func scrollBy(delta: CGFloat) {
        let newX = max(0, currentOffsetX + delta)
        scrollPosition.scrollTo(point: CGPoint(x: newX, y: 0))
    }

    private enum ScrollDirection {
        case left, right
    }

    @ViewBuilder
    private func carouselScrollArrow(direction: ScrollDirection, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background {
                    Circle().fill(Color.black.opacity(0.65))
                }
                .overlay {
                    Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.35), radius: 6, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
