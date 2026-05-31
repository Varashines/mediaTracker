import SwiftUI

struct HoverScaleEffect: ViewModifier {
    var scale: CGFloat = 1.04
    var shadowColor: Color = .black
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .shadow(color: shadowColor.opacity(isHovered ? 0.12 : 0), radius: 6, x: 0, y: 3)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
            .onHover { hovering in withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering } }
    }
}

extension View {
    func hoverScale(scale: CGFloat = 1.04, shadowColor: Color = .black) -> some View {
        modifier(HoverScaleEffect(scale: scale, shadowColor: shadowColor))
    }
}
