import SwiftUI
import SwiftData

struct CollectionPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Query(filter: #Predicate<MediaCollection> { $0.smartRulesData == nil }, sort: \MediaCollection.name) private var collections: [MediaCollection]
    let item: MediaItem
    @State private var isDoneHovered = false
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Text("Add to Collection")
                .font(AppTheme.Font.title3)
            
            if collections.isEmpty {
                VStack(spacing: AppTheme.Spacing.medium) {
                    Image(systemName: "folder.badge.plus")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No collections found.")
                        .foregroundStyle(.secondary)
                    Text("Create one from the My Collections hub.")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.small) {
                        ForEach(collections) { collection in
                            CollectionToggleRow(collection: collection, item: item)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                    .background(.secondary)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .scaleEffect(isDoneHovered ? 1.03 : 1.0)
            .shadow(color: .black.opacity(isDoneHovered ? 0.12 : 0), radius: 6, y: isDoneHovered ? 3 : 0)
            .onHover { hovering in
                withAnimation(AppTheme.Animation.springSnappy) { isDoneHovered = hovering }
            }
        }
        .padding(AppTheme.Spacing.xLarge)
        .background(AppTheme.Colors.surface(for: colorScheme))
    }
}

struct CollectionToggleRow: View {
    let collection: MediaCollection
    let item: MediaItem
    @State private var isHovered = false
    
    var isInCollection: Bool {
        item.collections.contains(where: { $0.id == collection.id })
    }
    
    var body: some View {
        Button {
            toggle()
        } label: {
            HStack {
                CollectionIconView(systemImage: collection.systemImage, font: AppTheme.Font.bodyMedium, color: .blue)
                    .frame(width: 24)
                Text(collection.name)
                    .font(AppTheme.Font.body)
                Spacer()
                Image(systemName: isInCollection ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isInCollection ? .blue : .secondary)
            }
            .padding(AppTheme.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.springSnappy) { isHovered = hovering }
        }
        .accessibilityLabel("\(collection.name), \(isInCollection ? "in collection" : "not in collection")")
        .accessibilityHint("Double tap to toggle")
    }
    
    private func toggle() {
        if isInCollection {
            collection.completedItemIDs.removeAll { $0 == item.id }
            item.collections.removeAll(where: { $0.id == collection.id })
        } else {
            item.collections.append(collection)
        }
        
        if let context = item.modelContext {
            SaveCoordinator.shared.requestSave(context)
        }
    }
}
