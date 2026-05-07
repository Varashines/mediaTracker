import SwiftUI
import SwiftData

struct RecentlyAddedRow: View {
    let items: [MediaThumbnailMetadata]
    let isFastScrolling: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(title: "Recently Added", icon: "clock.badge.checkmark", iconColor: .orange)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(items) { metadata in
                        NavigationLink(value: metadata.id) {
                            MediaThumbnailView(metadata: metadata, mode: .grid, isFastScrolling: isFastScrolling).id(metadata.versionHash)
                        }
                        .buttonStyle(.interactive)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 15)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollClipDisabled()
        }
        .compositingGroup()
        Divider().padding(.horizontal, 30).padding(.bottom, 20)
    }
}
