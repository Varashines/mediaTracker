import SwiftUI

struct FeedbackTestButton: View {
    let title: String
    let type: FeedbackManager.FeedbackType
    
    var body: some View {
        Button(title) {
            FeedbackManager.shared.trigger(type)
        }
        .buttonStyle(.interactive(feedback: type))
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05))
        .clipShape(Capsule())
    }
}
