import SwiftUI
import SwiftData

struct RecentlyAddedRow: View {
    let items: [MediaThumbnailMetadata]
    let isFastScrolling: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            SectionHeader(title: "Recently Added", icon: "clock.badge.checkmark", iconColor: .orange)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(items) { metadata in
                        NavigationLink(value: metadata.id) {
                            MediaThumbnailView(metadata: metadata, mode: .grid, isFastScrolling: isFastScrolling)
                                .equatable()
                                .id(metadata.versionHash)
                        }
                        .buttonStyle(.interactive)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.vertical, 15)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollClipDisabled()
        }
        .compositingGroup()
        Divider().padding(.horizontal, AppTheme.Spacing.pageMargin).padding(.bottom, 20)
    }
}
