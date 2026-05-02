import SwiftUI

struct EntranceStaggerModifier: ViewModifier {
    let index: Int
    @State private var isAppeared = false
    
    func body(content: Content) -> some View {
        content
            .offset(y: isAppeared ? 0 : 20)
            .opacity(isAppeared ? 1 : 0)
            .onAppear {
                let delay = Double(index % 24) * 0.03
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(delay)) {
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
