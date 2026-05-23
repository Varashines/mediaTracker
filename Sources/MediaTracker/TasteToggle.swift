import SwiftUI
import SwiftData

struct TasteToggle: View {
    @Bindable var item: MediaItem
    let themeColor: Color
    
    var body: some View {
        if item.modelContext != nil {
            HStack(spacing: 12) {
                TastePill(
                    label: "Love",
                    icon: "heart",
                    isSelected: item.taste == .love,
                    activeColor: .red,
                    action: { setTaste(.love) }
                )
                
                TastePill(
                    label: "Like",
                    icon: "hand.thumbsup",
                    isSelected: item.taste == .like,
                    activeColor: .blue,
                    action: { setTaste(.like) }
                )
                
                TastePill(
                    label: "Dislike",
                    icon: "hand.thumbsdown",
                    isSelected: item.taste == .dislike,
                    activeColor: .gray,
                    action: { setTaste(.dislike) }
                )
            }
        }
    }
    
    private func setTaste(_ val: TasteValue) {
        guard item.modelContext != nil else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            if item.taste == val {
                item.tasteValue = TasteValue.none.rawValue
                FeedbackManager.shared.trigger(.click)
            } else {
                item.tasteValue = val.rawValue
                
                switch val {
                case .love: FeedbackManager.shared.trigger(.tasteLove)
                case .like: FeedbackManager.shared.trigger(.tasteLike)
                case .dislike: FeedbackManager.shared.trigger(.tasteDislike)
                case .none: FeedbackManager.shared.trigger(.click)
                }
            }
        }
    }
}

#Preview("Taste Toggle") {
    VStack {
        Text("Rate this title:")
            .font(.headline)
        TasteToggle(item: MediaItem(id: "tt1", title: "Test Movie", overview: "A test movie", type: .movie), themeColor: .blue)
    }
    .padding()
    .modelContainer(try! ModelContainer(for: MediaItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
}
