import SwiftUI
import SwiftData

struct LoadingGridSkeleton: View {
    let selectedCategory: NavigationCategory
    let columns: [GridItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            if selectedCategory == .home {
                SectionHeader(title: "Coming Soon", icon: "calendar", iconColor: .secondary)
            } else {
                SectionHeader(title: "Loading Library...", icon: "hourglass", iconColor: .secondary)
            }
            
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(0..<12, id: \.self) { _ in
                    MediaThumbnailPlaceholder(mode: .grid)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
        }
        .padding(.top, 10)
    }
}
