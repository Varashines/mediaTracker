import SwiftUI

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
