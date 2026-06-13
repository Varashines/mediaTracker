import SwiftUI

struct ScrollVelocityTracker: View {
    @Binding var isFastScrolling: Bool
    @Binding var scrollTask: Task<Void, Never>?
    @State private var lastVelocityCheck = Date()
    // Coalesce velocity checks. SwiftUI re-fires `onChange(of: currentY)` on every pixel of
    // scroll, so we throttle to a sensible cadence and only spawn the debounce Task once
    // per actual sample.
    private let minSampleInterval: TimeInterval = 0.05
    private let velocityThreshold: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            let currentY = geo.frame(in: .global).minY
            Color.clear
                .onChange(of: currentY) { oldValue, newValue in
                    let now = Date()
                    guard now.timeIntervalSince(lastVelocityCheck) > minSampleInterval else { return }
                    lastVelocityCheck = now

                    let velocity = abs(newValue - oldValue)
                    if velocity > velocityThreshold && !isFastScrolling {
                        isFastScrolling = true
                    }

                    scheduleDebounce()
                }
        }
    }

    private func scheduleDebounce() {
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                isFastScrolling = false
            }
        }
    }
}
