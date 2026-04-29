import SwiftUI

struct InteractiveButtonStyle: ButtonStyle {
    var feedback: FeedbackManager.FeedbackType? = .click
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .onChange(of: configuration.isPressed) { oldValue, newValue in
                if newValue, let type = feedback {
                    FeedbackManager.shared.trigger(type)
                }
            }
    }
}

extension ButtonStyle where Self == InteractiveButtonStyle {
    static var interactive: InteractiveButtonStyle {
        InteractiveButtonStyle()
    }
    
    static func interactive(feedback: FeedbackManager.FeedbackType?) -> InteractiveButtonStyle {
        InteractiveButtonStyle(feedback: feedback)
    }
}
