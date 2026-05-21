import SwiftUI

#if !compiler(>=6.3)
public enum GlassEffectStyle {
    case regular
}

extension View {
    @ViewBuilder
    public func glassEffect(_ style: GlassEffectStyle = .regular) -> some View {
        self.background(.ultraThinMaterial)
    }
    
    @ViewBuilder
    public func glassEffect<S: Shape>(_ style: GlassEffectStyle, in shape: S) -> some View {
        self.background(.ultraThinMaterial, in: shape)
    }
}

extension Shape where Self == Capsule {
    public static var capsule: Capsule {
        Capsule()
    }
}

extension Shape where Self == RoundedRectangle {
    public static func rect(cornerRadius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}
#endif
