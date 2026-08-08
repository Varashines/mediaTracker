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
                HStack(spacing: AppTheme.Spacing.mini) {
                    Image(systemName: currentState.iconName)
                        .symbolEffect(.bounce, value: currentState)
                        .font(AppTheme.Font.label)
                    Text(currentState.displayName)
                        .font(AppTheme.Font.label)
                    Image(systemName: "chevron.down")
                        .font(AppTheme.Font.tiny)
                        .opacity(0.5)
                }
                .padding(.horizontal, AppTheme.Spacing.small)
                .padding(.vertical, AppTheme.Spacing.mini)
                .foregroundStyle(accent.isLightColor ? .black : .white)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .fill(accent.opacity(colorScheme == .dark ? 0.85 : 0.9))
                        )
                }
                .overlay {
                    Capsule()
                        .stroke(accent.opacity(0.3), lineWidth: 0.8)
                }
                .shadow(color: accent.opacity(isHovered ? 0.25 : 0), radius: 8, y: 3)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .scaleEffect(isHovered ? 1.04 : 1.0)
            .animation(AppTheme.Animation.springSnappy, value: isHovered)
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
