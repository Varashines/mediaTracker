import SwiftUI
import SwiftData

struct StatusPicker: View {
    @Bindable var item: MediaItem
    var onChange: ((MediaState?) -> Void)?

    var body: some View {
        if item.modelContext != nil && !item.isDeleted {
            HStack(spacing: 6) {
                Text("Watch State:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Status", selection: $item.state) {
                    ForEach(availableStates, id: \.self) { state in
                        Text(state.displayName)
                            .tag(state as MediaState?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)
                .labelsHidden()
                .onChange(of: item.state) { oldValue, newValue in
                    item.lastUpdated = Date()
                    item.lastInteractionDate = Date()
                    item.lastStateChangeDate = Date()
                    onChange?(newValue)
                }
            }
        }
    }
    
    private var availableStates: [MediaState] {
        guard item.modelContext != nil && !item.isDeleted else { return [] }
        return MediaItem.availableStates(for: item.type ?? .movie, progress: item.storedProgress)
    }
}
