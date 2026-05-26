import SwiftUI
import SwiftData

struct StatusPicker: View {
    @Bindable var item: MediaItem
    var onChange: ((MediaState?) -> Void)?
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    var body: some View {
        if item.modelContext != nil {
            let currentState = MediaState(rawValue: item.stateValue) ?? .wishlist
            let accent = stateColor(for: currentState)
            
            Menu {
                ForEach(availableStates, id: \.self) { state in
                    Button {
                        withAnimation(AppTheme.Animation.easeInOut) {
                            item.state = state
                            item.lastUpdated = Date()
                            onChange?(state)
                            if state == .completed {
                                FeedbackManager.shared.trigger(.markWatched)
                            } else {
                                FeedbackManager.shared.trigger(.stateChange)
                            }
                        }
                    } label: {
                        Label(state.displayName, systemImage: state.iconName)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: currentState.iconName)
                        .font(.system(size: 12, weight: .semibold))
                    Text(currentState.displayName)
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .opacity(0.5)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(accent)
                .background {
                    Capsule()
                        .fill(accent.opacity(isHovered ? 0.12 : 0.04))
                }
                .overlay {
                    Capsule()
                        .stroke(accent.opacity(isHovered ? 0.35 : 0.15), lineWidth: 0.8)
                }
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }
    
    private func stateColor(for state: MediaState) -> Color {
        return state.accentColor
    }
    
    private var availableStates: [MediaState] {
        guard item.modelContext != nil else { return [] }
        return MediaItem.availableStates(for: item.type ?? .movie, progress: item.storedProgress)
    }
}
