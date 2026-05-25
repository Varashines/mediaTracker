import SwiftUI
import SwiftData

struct GroupedMediaGrid: View {
    let groupedItems: [(String, [MediaThumbnailMetadata])]
    let selectedCategoryRef: NavigationCategory?
    let showingUpcomingOnly: Bool
    var viewModel: MediaViewModel
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let useCompactCards: Bool
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
                    
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        let groupArray = Array(groupMetadatas.enumerated())
                        ForEach(groupArray, id: \.element.id) { idx, metadata in
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
        .padding(.bottom, 24)
        .task(id: viewModel.selectedCollectionID) {
            guard let cid = viewModel.selectedCollectionID else {
                completedIDs = []
                return
            }
            let descriptor = FetchDescriptor<MediaCollection>(
                predicate: #Predicate { $0.id == cid },
                sortBy: [SortDescriptor(\.name)]
            )
            if let collection = try? modelContext.fetch(descriptor).first {
                completedIDs = Set(collection.completedItemIDs)
            }
        }
    }
    
    @ViewBuilder
    private func gridCell(for metadata: MediaThumbnailMetadata) -> some View {
        if !useCompactCards {
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
        } else {
            CompactThumbnailView(
                metadata: metadata,
                isFastScrolling: isFastScrolling,
                isCompletedInCollection: completedIDs.contains(metadata.itemID)
            )
            .id(metadata.versionHash)
        }
    }

    @Environment(\.modelContext) private var modelContext
}
