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
                    activeColor: Color(white: 0.35),
                    action: { setTaste(.dislike) }
                )
            }
        }
    }
    
    private func setTaste(_ val: TasteValue) {
        guard item.modelContext != nil else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            let isRemoving = item.taste == val
            if isRemoving {
                item.applyTasteChange(.none)
                FeedbackManager.shared.trigger(.click)
            } else {
                item.applyTasteChange(val)
                switch val {
                case .love: FeedbackManager.shared.trigger(.tasteLove)
                case .like: FeedbackManager.shared.trigger(.tasteLike)
                case .dislike: FeedbackManager.shared.trigger(.tasteDislike)
                case .none: FeedbackManager.shared.trigger(.click)
                }
            }
            AppErrorState.shared.showToast(
                isRemoving ? "Rating removed" : val.rawValue,
                style: .success
            )
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

struct TastePill: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let activeColor: Color
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "\(icon).fill" : icon)
                Text(label)
            }
            .font(AppTheme.Font.bodyBold)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : .primary.opacity(0.8))
            .background {
                if isSelected {
                    activeColor
                } else {
                    Color.primary.opacity(isHovered ? 0.08 : 0.05)
                        .background(.ultraThinMaterial)
                }
            }
            .clipShape(Capsule())
            .scaleEffect(isHovered ? 1.04 : 1.0)
            .shadow(color: isSelected ? activeColor.opacity(isHovered ? 0.35 : 0.3) : .clear, radius: isHovered ? 10 : 8, x: 0, y: isHovered ? 6 : 4)
        }
        .buttonStyle(.interactive(feedback: nil))
        .onHover { isHovered = $0 }
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
    }
}
