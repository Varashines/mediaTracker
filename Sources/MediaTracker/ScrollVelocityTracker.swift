import SwiftUI

struct ScrollVelocityTracker: View {
    @Binding var isFastScrolling: Bool
    @Binding var scrollTimer: Timer?
    
    var body: some View {
        GeometryReader { geo in
            let currentY = geo.frame(in: .global).minY
            Color.clear
                .onChange(of: currentY) { oldValue, newValue in
                    let velocity = abs(newValue - oldValue)
                    if velocity > 30 && !isFastScrolling {
                        isFastScrolling = true
                    }
                    
                    scrollTimer?.invalidate()
                    scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
                        Task { @MainActor in
                            withAnimation(.smooth) {
                                isFastScrolling = false
                            }
                        }
                    }
                }
        }
    }
}
