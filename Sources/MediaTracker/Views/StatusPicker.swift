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
                            item.applyStateChange(state)
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
                        .symbolEffect(.bounce, value: currentState)
                        .font(AppTheme.Font.label)
                    Text(currentState.displayName)
                        .font(AppTheme.Font.label)
                    Image(systemName: "chevron.down")
                        .font(AppTheme.Font.tiny)
                        .opacity(0.5)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(accent.isLightColor ? .black : .white)
                .background {
                    Capsule()
                        .fill(accent)
                }
                .overlay {
                    Capsule()
                        .stroke(accent.opacity(0.3), lineWidth: 0.8)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Status: \(currentState.displayName)")
            .accessibilityHint("Double tap to change status")
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
