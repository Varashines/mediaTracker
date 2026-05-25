import SwiftUI
import SwiftData

struct CollectionPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MediaCollection.name) private var collections: [MediaCollection]
    let item: MediaItem
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Add to Collection")
                .font(.title2.bold())
            
            if collections.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.plus")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No collections found.")
                        .foregroundStyle(.secondary)
                    Text("Create one from the My Collections hub.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(collections) { collection in
                            CollectionToggleRow(collection: collection, item: item)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.vertical, 12)
            .background(Color.blue)
            .foregroundStyle(.white)
            .cornerRadius(AppTheme.Radius.medium)
        }
        .padding(32)
        .frame(width: 350, height: 450)
    }
}

struct CollectionToggleRow: View {
    let collection: MediaCollection
    let item: MediaItem
    
    var isInCollection: Bool {
        item.collections.contains(where: { $0.id == collection.id })
    }
    
    var body: some View {
        Button {
            toggle()
        } label: {
            HStack {
                Image(systemName: collection.systemImage)
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                Text(collection.name)
                Spacer()
                Image(systemName: isInCollection ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isInCollection ? .blue : .secondary)
            }
            .padding()
            .background(Color.primary.opacity(0.05))
            .cornerRadius(AppTheme.Radius.medium)
        }
        .buttonStyle(.plain)
    }
    
    private func toggle() {
        if isInCollection {
            item.collections.removeAll(where: { $0.id == collection.id })
            collection.items.removeAll(where: { $0.id == item.id })
        } else {
            item.collections.append(collection)
            collection.items.append(item)
        }
        
        // SwiftData might need explicit save or context refresh for relationships sometimes
        try? item.modelContext?.save()
    }
}
