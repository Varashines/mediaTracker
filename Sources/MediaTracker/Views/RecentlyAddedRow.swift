import SwiftUI
import SwiftData

struct RecentlyAddedRow: View {
    let items: [MediaThumbnailMetadata]
    let isFastScrolling: Bool
    let namespace: Namespace.ID
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            SectionHeader(title: "Recently Added", icon: "clock.badge.checkmark", iconColor: .orange)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(items) { metadata in
                        NavigationLink(value: metadata.id) {
                            MediaThumbnailView(metadata: metadata, mode: .grid, namespace: namespace, isFastScrolling: isFastScrolling)
                                .equatable()
                                .compositingGroupIfNeeded()
                        }
                        .buttonStyle(.interactive)
                        .transition(.mediaRowArrival)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.vertical, 15)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollClipDisabled()
        }
        .padding(.top, AppTheme.Spacing.medium)
        Divider().padding(.horizontal, AppTheme.Spacing.pageMargin).padding(.bottom, 20)
    }
}
