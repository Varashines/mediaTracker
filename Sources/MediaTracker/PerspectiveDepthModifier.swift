import SwiftUI

struct PerspectiveDepthModifier: ViewModifier {
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .blur(radius: isActive ? 0 : 15)
            .scaleEffect(isActive ? 1.0 : 0.92)
            .offset(y: isActive ? 0 : 20)
            .allowsHitTesting(isActive)
            .zIndex(isActive ? 1 : 0)
    }
}
