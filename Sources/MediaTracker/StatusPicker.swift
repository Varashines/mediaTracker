import SwiftUI
import SwiftData

struct StatusPicker: View {
    @Bindable var item: MediaItem
    var onChange: ((MediaState?) -> Void)?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if item.modelContext != nil {
            let currentState = item.state ?? .wishlist
            let accent = stateColor(for: currentState)
            
            Menu {
                ForEach(availableStates, id: \.self) { state in
                    Button {
                        withAnimation(.smooth) {
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
                        .font(.system(size: 13, weight: .bold))
                    Text(currentState.displayName)
                        .font(.system(size: 13, weight: .bold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .opacity(0.6)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(currentState == .wishlist && colorScheme == .light ? .black : .white)
                .background(accent)
                .clipShape(Capsule())
                .shadow(color: accent.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
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
