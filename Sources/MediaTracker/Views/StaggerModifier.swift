import SwiftUI

struct StaggerModifier: ViewModifier {
    let index: Int
    var isFastScrolling: Bool = false
    var modulo: Int = 8
    var delayPerStep: TimeInterval = 0.05
    var verticalOffset: CGFloat = 8

    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared || isFastScrolling ? 1 : 0)
            .offset(y: hasAppeared || isFastScrolling ? 0 : verticalOffset)
            .onAppear {
                if isFastScrolling || hasAppeared { return }
                withAnimation(AppTheme.Animation.springGentle.delay(Double(index % modulo) * delayPerStep)) {
                    hasAppeared = true
                }
            }
    }
}
