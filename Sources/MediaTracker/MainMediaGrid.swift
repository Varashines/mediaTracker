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
    let useCompactCards: Bool
    let onLoadMore: () -> Void
    let columns: [GridItem]

    @State private var completedIDs: Set<String> = []

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            let baseItems = showingUpcomingOnly ? Array(items.dropFirst(featuredCount)) : items

            ForEach(Array(baseItems.enumerated()), id: \.element.id) { idx, metadata in
                NavigationLink(value: metadata.id) {
                    gridCell(for: metadata, at: idx, in: baseItems)
                }
                .buttonStyle(.interactive)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
        .padding(.top, 8)
        .padding(.bottom, 24)
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
    private func gridCell(for metadata: MediaThumbnailMetadata, at idx: Int, in baseItems: [MediaThumbnailMetadata]) -> some View {
        if !useCompactCards {
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
                if !isFastScrolling {
                    let prefetchCount = 12
                    if idx + 1 < baseItems.count {
                        let endIdx = min(idx + 1 + prefetchCount, baseItems.count)
                        let urlsToPrefetch = baseItems[idx+1..<endIdx]
                            .compactMap { $0.posterURL }
                            .compactMap { URL(string: $0) }
                        if !urlsToPrefetch.isEmpty {
                            PrefetchManager.shared.prefetch(urls: urlsToPrefetch, targetSize: .thumbSmall)
                        }
                    }
                }
            }
        } else {
            CompactThumbnailView(
                metadata: metadata,
                isFastScrolling: isFastScrolling,
                isCompletedInCollection: completedIDs.contains(metadata.itemID)
            )
            .id(metadata.versionHash)
            .onAppear {
                if metadata.id == items.last?.id {
                    onLoadMore()
                }
                if !isFastScrolling {
                    let prefetchCount = 12
                    if idx + 1 < baseItems.count {
                        let endIdx = min(idx + 1 + prefetchCount, baseItems.count)
                        let urlsToPrefetch = baseItems[idx+1..<endIdx]
                            .compactMap { $0.posterURL }
                            .compactMap { URL(string: $0) }
                        if !urlsToPrefetch.isEmpty {
                            PrefetchManager.shared.prefetch(urls: urlsToPrefetch, targetSize: .thumbSmall)
                        }
                    }
                }
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
}
