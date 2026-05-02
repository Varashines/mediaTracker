import SwiftUI
import SwiftData

struct TasteToggle: View {
    @Bindable var item: MediaItem
    let themeColor: Color
    
    var body: some View {
        if item.modelContext != nil && !item.isDeleted {
            HStack(spacing: 12) {
                TastePill(
                    label: "Love",
                    icon: "heart",
                    isSelected: item.tasteValue == "Love",
                    activeColor: .red,
                    action: { setTaste("Love") }
                )
                
                TastePill(
                    label: "Like",
                    icon: "hand.thumbsup",
                    isSelected: item.tasteValue == "Like",
                    activeColor: .blue,
                    action: { setTaste("Like") }
                )
                
                TastePill(
                    label: "Dislike",
                    icon: "hand.thumbsdown",
                    isSelected: item.tasteValue == "Dislike",
                    activeColor: .gray,
                    action: { setTaste("Dislike") }
                )
            }
        }
    }
    
    private func setTaste(_ val: String) {
        guard item.modelContext != nil && !item.isDeleted else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if item.tasteValue == val {
                item.tasteValue = "None"
                FeedbackManager.shared.trigger(.click)
            } else {
                item.tasteValue = val
                
                // Creative Feedback Personality
                switch val {
                case "Love": FeedbackManager.shared.trigger(.tasteLove)
                case "Like": FeedbackManager.shared.trigger(.tasteLike)
                case "Dislike": FeedbackManager.shared.trigger(.tasteDislike)
                default: FeedbackManager.shared.trigger(.click)
                }
            }
        }
    }
}
