import SwiftUI
import SwiftData

struct GroupedMediaGrid: View {
    let groupedItems: [(String, [MediaThumbnailMetadata])]
    let selectedCategoryRef: NavigationCategory?
    var viewModel: MediaViewModel
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let disableHover: Bool
    let columns: [GridItem]
    
    @State private var completedIDs: Set<String> = []
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 60) {
            ForEach(groupedItems, id: \.0) { (key, groupMetadatas) in
                VStack(alignment: .leading, spacing: 25) {
                    SectionHeader(
                        title: key,
                        icon: (key == "Coming Soon" && selectedCategoryRef == .home) ? "calendar" : nil,
                        iconColor: .secondary
                    )
                    
                    LazyVGrid(columns: columns, alignment: .leading, spacing: AppTheme.Spacing.grid) {
                        ForEach(groupMetadatas, id: \.id) { metadata in
                                NavigationLink(value: metadata.id) {
                                    gridCell(for: metadata)
                                }
                                .buttonStyle(.interactive)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .padding(.top, 10)
                }
            }
        }
        .padding(.bottom, 32)
        .loadCompletedCollectionIDs(for: viewModel.collection.selectedCollectionID, into: $completedIDs)
    }
    
    @ViewBuilder
    private func gridCell(for metadata: MediaThumbnailMetadata) -> some View {
        MediaThumbnailView(
            metadata: metadata,
            mode: .grid,
            showTypeBadge: viewModel.filter.currentGroupBy != .category,
            namespace: namespace,
            isFastScrolling: isFastScrolling,
            disableHover: disableHover,
            isCompletedInCollection: completedIDs.contains(metadata.itemID),
            selectedCollectionID: viewModel.collection.selectedCollectionID
        )
        .equatable()
    }

    @Environment(\.modelContext) private var modelContext
}
