import SwiftUI
import SwiftData

struct StatusPicker: View {
    @Bindable var item: MediaItem
    var onChange: ((MediaState?) -> Void)?
    @Environment(\.modelContext) private var modelContext
    @Query private var watchCycles: [WatchCycle]
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    var body: some View {
        if item.modelContext != nil {
            let currentState = MediaState(rawValue: item.stateValue) ?? .wishlist
            let accent = currentState.accentColor
            
            Menu {
                ForEach(availableStates, id: \.self) { state in
                    Button {
                        withAnimation(AppTheme.Animation.easeInOut) {
                            item.state = state
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
                if hasPausedRewatch {
                    Divider()
                    Button {
                        guard item.modelContext != nil,
                              WatchHistoryCoordinator.resumePausedRewatch(item: item, context: modelContext) != nil else { return }
                        item.syncCachedProperties(dirty: [.progress, .badge])
                        SaveCoordinator.shared.requestSave(modelContext)
                        MediaStateService.shared.postMediaStateChanged(itemID: item.persistentModelID)
                        FeedbackManager.shared.trigger(.stateChange)
                    } label: {
                        Label(
                            hasActiveCycle ? "Finish current cycle to resume" : "Resume Paused Rewatch",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .disabled(hasActiveCycle)
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
                .foregroundStyle(accent.readableForeground)
                .background {
                    // Flat accent fill — material blur on the status capsule
                    // was unnecessary GPU work on the Detail header.
                    Capsule()
                        .fill(accent.opacity(colorScheme == .dark ? 0.85 : 0.9))
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
    
    private var hasActiveCycle: Bool {
        watchCycles.contains { $0.mediaID == item.id && $0.state == .active }
    }

    private var hasPausedRewatch: Bool {
        watchCycles.contains {
            $0.mediaID == item.id && $0.state == .paused && $0.isRewatch
        }
    }

    private var availableStates: [MediaState] {
        guard item.modelContext != nil else { return [] }
        return MediaItem.availableStates(for: item.type ?? .movie, progress: item.storedProgress)
    }
}
