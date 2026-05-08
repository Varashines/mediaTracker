import SwiftUI
import SwiftData

struct MainMediaGrid: View {
    let items: [MediaThumbnailMetadata]
    let featuredCount: Int
    let showingUpcomingOnly: Bool
    let isCategoryPage: Bool
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let selectedCollectionID: UUID?
    let onLoadMore: () -> Void
    let columns: [GridItem]

    @Query private var collections: [MediaCollection]

    private var completedIDs: Set<String> {
        if let cid = selectedCollectionID,
           let collection = collections.first(where: { $0.id == cid }) {
            return Set(collection.completedItemIDs)
        }
        return []
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
            let baseItems = showingUpcomingOnly ? Array(items.dropFirst(featuredCount)) : items

            ForEach(Array(baseItems.enumerated()), id: \.element.id) { idx, metadata in
                NavigationLink(value: metadata.id) {
                    MediaThumbnailView(
                        metadata: metadata, 
                        mode: .grid, 
                        showTypeBadge: !isCategoryPage, 
                        isUpcomingSection: showingUpcomingOnly, 
                        namespace: namespace, 
                        staggerIndex: idx, 
                        isFastScrolling: isFastScrolling, 
                        isCompletedInCollection: completedIDs.contains(metadata.itemID),
                        selectedCollectionID: selectedCollectionID
                    )
                    .id(metadata.versionHash)
                    .entranceStagger(index: idx)
                    .onAppear {
                        if metadata.id == items.last?.id {
                            onLoadMore()
                        }
                        
                        // Phase 4 Optimization: Predictive Prefetching
                        if isFastScrolling {
                            let prefetchCount = 12 // Look ahead ~2 rows
                            if idx + 1 < baseItems.count {
                                let endIdx = min(idx + 1 + prefetchCount, baseItems.count)
                                let urlsToPrefetch = baseItems[idx + 1..<endIdx]
                                    .compactMap { $0.posterURL }
                                    .compactMap { URL(string: $0) }
                                
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
        .padding(.top, 20)
        .padding(.bottom, 40)
    }
}
