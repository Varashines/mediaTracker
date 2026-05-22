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
        LazyVStack(alignment: .leading, spacing: 60) {
            ForEach(groupedItems, id: \.0) { (key, groupMetadatas) in
                VStack(alignment: .leading, spacing: 25) {
                    SectionHeader(
                        title: key,
                        icon: (key == "Coming Soon" && selectedCategoryRef == .home) ? "calendar" : nil,
                        iconColor: .secondary
                    )
                    
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        let groupArray = Array(groupMetadatas.enumerated())
                        ForEach(groupArray, id: \.element.id) { idx, metadata in
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
                                .onAppear {
                                    // Phase 4 Optimization: Predictive Prefetching
                                    if isFastScrolling {
                                        let prefetchCount = 8
                                        let endIdx = min(idx + 1 + prefetchCount, groupArray.count)
                                        if idx + 1 < groupArray.count {
                                            let slice = groupArray[(idx + 1)..<endIdx]
                                            let elements: [MediaThumbnailMetadata] = slice.map { $0.element }
                                            let urlsToPrefetch: [URL] = elements.compactMap { $0.posterURL }.compactMap { URL(string: $0) }
                                            
                                            if !urlsToPrefetch.isEmpty {
                                                ImageCache.shared.prewarmImages(urls: urlsToPrefetch, targetSize: CGSize(width: 160, height: 240), priority: .low)
                                            }
                                        }
                                    }
                                }
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
