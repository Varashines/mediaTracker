import SwiftUI
import SwiftData

struct StatusPicker: View {
    @Bindable var item: MediaItem
    var onChange: ((MediaState?) -> Void)?
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    var body: some View {
        if item.modelContext != nil {
            let currentState = item.state ?? .wishlist
            let accent = stateColor(for: currentState)
            
            Menu {
                ForEach(availableStates, id: \.self) { state in
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            item.state = state
                            item.lastUpdated = Date()
                            onChange?(state)
                            FeedbackManager.shared.trigger(.click)
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
        switch state {
        case .active, .rewatching:
            return Color.fromOKLCH(l: 0.55, c: 0.2, h: 250) // Blue
        case .wishlist:
            return Color.fromOKLCH(l: 0.7, c: 0.18, h: 75)  // Amber/Gold
        case .onHold:
            return Color.fromOKLCH(l: 0.5, c: 0.05, h: 250) // Slate Gray
        case .dropped:
            return Color.fromOKLCH(l: 0.6, c: 0.15, h: 25)  // Soft Red
        case .completed:
            return Color.fromOKLCH(l: 0.65, c: 0.2, h: 145) // Emerald Green
        }
    }
    
    private var availableStates: [MediaState] {
        guard item.modelContext != nil else { return [] }
        return MediaItem.availableStates(for: item.type ?? .movie, progress: item.storedProgress)
    }
}
