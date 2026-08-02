import SwiftUI

struct StaggerModifier: ViewModifier {
    let index: Int
    var isFastScrolling: Bool = false
    var modulo: Int = 8
    var delayPerStep: TimeInterval = 0.05
    var verticalOffset: CGFloat = 8

    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        let skipAnimation = index >= modulo * 2
        content
            .opacity(hasAppeared || isFastScrolling || skipAnimation ? 1 : 0)
            .offset(y: hasAppeared || isFastScrolling || skipAnimation ? 0 : verticalOffset)
            .onAppear {
                if isFastScrolling || hasAppeared || skipAnimation {
                    hasAppeared = true
                    return
                }
                withAnimation(AppTheme.Animation.springGentle.delay(Double(index % modulo) * delayPerStep)) {
                    hasAppeared = true
                }
            }
    }
}
