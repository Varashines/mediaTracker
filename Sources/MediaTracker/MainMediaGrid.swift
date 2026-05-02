import SwiftUI
import SwiftData

struct MainMediaGrid: View {
    let items: [MediaThumbnailMetadata]
    let featuredCount: Int
    let showingUpcomingOnly: Bool
    let isCategoryPage: Bool
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let onLoadMore: () -> Void
    let columns: [GridItem]
    
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
            let baseItems = showingUpcomingOnly ? Array(items.dropFirst(featuredCount)) : items
            
            ForEach(baseItems.indices, id: \.self) { idx in
                let metadata = baseItems[idx]
                NavigationLink(value: metadata.id) {
                    MediaThumbnailView(metadata: metadata, mode: .grid, showTypeBadge: !isCategoryPage, isUpcomingSection: showingUpcomingOnly, namespace: namespace, staggerIndex: idx, isFastScrolling: isFastScrolling)
                        .id(metadata.versionHash)
                        .entranceStagger(index: idx)
                        .onAppear {
                            if metadata.id == items.last?.id {
                                onLoadMore()
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
