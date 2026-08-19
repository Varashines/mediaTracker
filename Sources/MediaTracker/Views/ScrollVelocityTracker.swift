import SwiftUI

/// Legacy GeometryReader tracker (macOS 14 fallback). Kept for hybrid mode.
struct ScrollVelocityTracker: View {
    @Binding var isFastScrolling: Bool
    @Binding var scrollTask: Task<Void, Never>?
    @State private var lastOffset: CGFloat = 0

    private let velocityThreshold: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    lastOffset = geo.frame(in: .global).minY
                }
                .onChange(of: geo.frame(in: .global).minY) { _, newValue in
                    let velocity = abs(newValue - lastOffset)
                    lastOffset = newValue

                    if velocity > velocityThreshold && !isFastScrolling {
                        isFastScrolling = true
                    }

                    if isFastScrolling {
                        scrollTask?.cancel()
                        scrollTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 150_000_000)
                            guard !Task.isCancelled else { return }
                            isFastScrolling = false
                        }
                    }
                }
        }
        .frame(height: 0)
    }
}

// MARK: - macOS 15 fast-path: coalesced scroll tracking

private struct FastScrollingModifier: ViewModifier {
    @Binding var isFastScrolling: Bool
    @Binding var scrollTask: Task<Void, Never>?
    @State private var lastOffset: CGFloat = 0
    private let velocityThreshold: CGFloat = 40

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y
                } action: { _, newValue in
                    let velocity = abs(newValue - lastOffset)
                    lastOffset = newValue
                    if velocity > velocityThreshold && !isFastScrolling {
                        isFastScrolling = true
                    }
                    if isFastScrolling {
                        scrollTask?.cancel()
                        scrollTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 150_000_000)
                            guard !Task.isCancelled else { return }
                            isFastScrolling = false
                        }
                    }
                }
        } else {
            content.background {
                ScrollVelocityTracker(isFastScrolling: $isFastScrolling, scrollTask: $scrollTask)
            }
        }
    }
}

extension View {
    /// Hybrid tracker: macOS 15 uses coalesced `onScrollGeometryChange`, older falls back to `GeometryReader`.
    /// Attach to the `ScrollView` itself (not its content).
    func trackFastScrolling(isFastScrolling: Binding<Bool>, scrollTask: Binding<Task<Void, Never>?>) -> some View {
        modifier(FastScrollingModifier(isFastScrolling: isFastScrolling, scrollTask: scrollTask))
    }
}
