import SwiftUI

struct ScrollVelocityTracker: View {
    @Binding var isFastScrolling: Bool
    @Binding var scrollTask: Task<Void, Never>?
    @State private var scrollOffset: CGFloat = 0
    @State private var lastOffset: CGFloat = 0
    @State private var sampleTask: Task<Void, Never>?

    private let sampleInterval: TimeInterval = 0.05
    private let velocityThreshold: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    scrollOffset = geo.frame(in: .global).minY
                    lastOffset = scrollOffset
                    startSampling(geo: geo)
                }
                .onDisappear {
                    sampleTask?.cancel()
                }
        }
        .frame(height: 0)
    }

    private func startSampling(geo: GeometryProxy) {
        sampleTask?.cancel()
        sampleTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(sampleInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                let current = geo.frame(in: .global).minY
                let velocity = abs(current - lastOffset)
                lastOffset = current

                if velocity > velocityThreshold && !isFastScrolling {
                    isFastScrolling = true
                }

                if isFastScrolling {
                    scheduleDebounce()
                }
            }
        }
    }

    private func scheduleDebounce() {
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            isFastScrolling = false
        }
    }
}
