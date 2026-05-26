import SwiftUI
import SwiftData

struct MainMediaGrid: View {
    let items: [MediaThumbnailMetadata]
    let featuredCount: Int
    let isCategoryPage: Bool
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let disableHover: Bool
    let selectedCollectionID: UUID?
    let onLoadMore: () -> Void
    let columns: [GridItem]
    let isLoadingMore: Bool

    @State private var completedIDs: Set<String> = []

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, metadata in
                NavigationLink(value: metadata.id) {
                    gridCell(for: metadata, at: idx)
                }
                .buttonStyle(.interactive)
            }
            
            if isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        }
        .padding(AppTheme.Spacing.pageMargin)
        .task(id: selectedCollectionID) {
            guard let cid = selectedCollectionID else {
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
    private func gridCell(for metadata: MediaThumbnailMetadata, at idx: Int) -> some View {
        MediaThumbnailView(
            metadata: metadata,
            mode: .grid,
            showTypeBadge: !isCategoryPage,
            namespace: namespace,
            staggerIndex: idx,
            isFastScrolling: isFastScrolling,
            disableHover: disableHover,
            isCompletedInCollection: completedIDs.contains(metadata.itemID),
            selectedCollectionID: selectedCollectionID
        )
        .id(metadata.versionHash)
        .onAppear {
            if metadata.id == items.last?.id {
                onLoadMore()
            }
            if !isFastScrolling {
                let prefetchCount = 12
                if idx + 1 < items.count {
                    let endIdx = min(idx + 1 + prefetchCount, items.count)
                    let urlsToPrefetch = items[idx+1..<endIdx]
                        .compactMap { $0.posterURL }
                        .compactMap { URL(string: $0) }
                    if !urlsToPrefetch.isEmpty {
                        PrefetchManager.shared.prefetch(urls: urlsToPrefetch, targetSize: .thumbSmall)
                    }
                }
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
}
