import SwiftUI
import SwiftData

struct GroupedMediaGrid: View {
    let groupedItems: [(String, [MediaThumbnailMetadata])]
    let selectedCategoryRef: NavigationCategory?
    let showingUpcomingOnly: Bool
    var viewModel: MediaViewModel
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let columns: [GridItem]
    
    @Query private var collections: [MediaCollection]
    
    private var completedIDs: Set<String> {
        if let cid = viewModel.selectedCollectionID,
           let collection = collections.first(where: { $0.id == cid }) {
            return Set(collection.completedItemIDs)
        }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 60) {
            ForEach(groupedItems, id: \.0) { (key, groupMetadatas) in
                VStack(alignment: .leading, spacing: 25) {
                    SectionHeader(
                        title: key,
                        icon: (key == "Coming Soon" && selectedCategoryRef == .home) ? "calendar" : nil,
                        iconColor: .secondary
                    )
                    
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(groupMetadatas) { metadata in
                            NavigationLink(value: metadata.id) {
                                MediaThumbnailView(
                                    metadata: metadata, 
                                    mode: .grid, 
                                    showTypeBadge: viewModel.currentGroupBy != .category, 
                                    isUpcomingSection: showingUpcomingOnly, 
                                    namespace: namespace, 
                                    isFastScrolling: isFastScrolling, 
                                    isCompletedInCollection: completedIDs.contains(metadata.itemID),
                                    selectedCollectionID: viewModel.selectedCollectionID
                                )
                                .id(metadata.versionHash)
                                .entranceStagger(index: 0)
                            }
                            .buttonStyle(.interactive)
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 10)
                }
            }
        }
        .padding(.bottom, 40)
    }
}
