import SwiftUI

struct EntranceStaggerModifier: ViewModifier {
    let index: Int
    @State private var isAppeared = false
    
    func body(content: Content) -> some View {
        content
            .offset(y: isAppeared ? 0 : 20)
            .opacity(isAppeared ? 1 : 0)
            .onAppear {
                let delay = Double(index % 12) * 0.02
                withAnimation(.smooth(duration: 0.4).delay(delay)) {
                    isAppeared = true
                }
            }
    }
}

extension View {
    func entranceStagger(index: Int) -> some View {
        modifier(EntranceStaggerModifier(index: index))
    }
}
