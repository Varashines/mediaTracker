import SwiftUI

/// Legacy GeometryReader tracker (macOS 14 fallback). Kept for hybrid mode.
struct ScrollVelocityTracker: View {
    @Binding var isFastScrolling: Bool
    @Binding var scrollTask: Task<Void, Never>?
    @State private var lastOffset: CGFloat = 0
    @State private var lastTimestamp: Date = .distantPast

    private let velocityThreshold: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    lastOffset = geo.frame(in: .global).minY
                }
                .onChange(of: geo.frame(in: .global).minY) { _, newValue in
                    let now = Date()
                    let dt = max(now.timeIntervalSince(lastTimestamp), 1.0 / 120.0)
                    let velocity = abs(newValue - lastOffset) / CGFloat(dt)
                    lastOffset = newValue
                    lastTimestamp = now

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
    @State private var lastTimestamp: Date = .distantPast
    private let velocityThreshold: CGFloat = 40

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y
                } action: { _, newValue in
                    let now = Date()
                    let dt = max(now.timeIntervalSince(lastTimestamp), 1.0 / 120.0)
                    let velocity = abs(newValue - lastOffset) / CGFloat(dt)
                    lastOffset = newValue
                    lastTimestamp = now
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

/// Local-state fast-scroll tracker that injects into `EnvironmentValues.isFastScrolling`.
/// Only this modifier re-evaluates when the flag flips — not the parent screen body.
private struct FastScrollingEnvModifier: ViewModifier {
    @State private var isFastScrolling = false
    @State private var scrollTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .trackFastScrolling(isFastScrolling: $isFastScrolling, scrollTask: $scrollTask)
            .environment(\.isFastScrolling, isFastScrolling)
            .onChange(of: SleepManager.shared.isAsleep) { _, isAsleep in
                if isAsleep {
                    scrollTask?.cancel()
                    scrollTask = nil
                    isFastScrolling = false
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

    /// Self-contained tracker: owns local state and publishes via environment.
    /// Parent screens should not hold `@State isFastScrolling` — that re-renders the whole tree.
    func trackFastScrollingEnv() -> some View {
        modifier(FastScrollingEnvModifier())
    }
}
