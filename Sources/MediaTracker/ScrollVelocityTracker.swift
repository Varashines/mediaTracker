import SwiftUI

struct ScrollVelocityTracker: View {
    @Binding var isFastScrolling: Bool
    @Binding var scrollTask: Task<Void, Never>?
    
    var body: some View {
        GeometryReader { geo in
            let currentY = geo.frame(in: .global).minY
            Color.clear
                .onChange(of: currentY) { oldValue, newValue in
                    let velocity = abs(newValue - oldValue)
                    if velocity > 30 && !isFastScrolling {
                        isFastScrolling = true
                    }
                    
                    scrollTask?.cancel()
                    scrollTask = Task {
                        try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s
                        guard !Task.isCancelled else { return }
                        
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isFastScrolling = false
                            }
                        }
                    }
                }
        }
    }
}
