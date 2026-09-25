import SwiftUI
import SwiftData

struct TasteToggle: View {
    @Bindable var item: MediaItem
    let themeColor: Color
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        if item.modelContext != nil {
            // Segmented control: one dynamic-width capsule behind all three
            // options instead of three separate pill backgrounds.
            HStack(spacing: 2) {
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
            .padding(3)
            .background {
                Capsule().fill(Color.primary.opacity(0.06))
            }
            .clipShape(Capsule())
        }
    }
    
    private func setTaste(_ val: TasteValue) {
        guard item.modelContext != nil else { return }
        let isRemoving = item.taste == val
        let newTaste: TasteValue = isRemoving ? .none : val

        // Mutate on the click frame — pill `.animation(value: isSelected)` handles the visual.
        // Do NOT wrap commit/toast/save here: they block the frame and delay the tap feedback.
        item.tasteValue = newTaste.rawValue
        item.lastInteractionDate = Date()

        FeedbackManager.shared.trigger(
            isRemoving ? .click : {
                switch val {
                case .love: return .tasteLove
                case .like: return .tasteLike
                case .dislike: return .tasteDislike
                case .none: return .click
                }
            }()
        )

        Task { @MainActor [weak item] in
            guard let item, item.modelContext != nil else { return }
            // Taste is not an input to badge/searchable — dirty [] only refreshes
            // storedIsUpcoming (cheap). Save + taste caches run off this frame.
            item.syncCachedProperties(dirty: [])
            if let context = item.modelContext {
                SaveCoordinator.shared.requestSave(context)
            }
            MediaStateService.shared.postMediaStateChanged(itemID: item.persistentModelID)
            MediaStateService.shared.postTasteChanged()
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
            HStack(spacing: AppTheme.Spacing.mini) {
                Image(systemName: isSelected ? "\(icon).fill" : icon)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isSelected)
                Text(label)
                    .contentTransition(.opacity)
            }
            .font(AppTheme.Font.bodyBold)
            .padding(.horizontal, AppTheme.Spacing.small)
            .padding(.vertical, AppTheme.Spacing.tiny)
            .foregroundStyle(isSelected ? .white : (isHovered ? .primary : .primary.opacity(0.75)))
            .background {
                // Opacity fill so select/deselect crossfades under one spring —
                // a bare `if isSelected { color }` pops with no interpolation.
                activeColor
                    .opacity(isSelected ? 1 : 0)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .scaleEffect(isSelected ? 1.05 : (isHovered ? 1.04 : 1.0))
            .shadow(color: isSelected ? activeColor.opacity(0.2) : .clear, radius: AppTheme.Shadow.card.radius, y: AppTheme.Shadow.card.y)
        }
        .buttonStyle(.interactive(feedback: nil))
        .onHover { isHovered = $0 }
        // One spring drives hover + selection so enter, exit, and taste change stay in sync.
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .animation(AppTheme.Animation.springSnappy, value: isSelected)
    }
}

struct TasteBadgeView: View {
    let tasteValue: String?
    var size: CGFloat = 4.5
    var padding: CGFloat = 2

    var body: some View {
        switch tasteValue {
        case "Loved", "Love":
            badge("heart.fill", color: .pink)
        case "Liked", "Like":
            badge("hand.thumbsup.fill", color: .blue)
        case "Disliked", "Dislike":
            badge("hand.thumbsdown.fill", color: .gray)
        default:
            EmptyView()
        }
    }

    private func badge(_ icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.white)
            .padding(padding)
            .background(color.opacity(0.9), in: Circle())
            .padding(padding)
    }
}
