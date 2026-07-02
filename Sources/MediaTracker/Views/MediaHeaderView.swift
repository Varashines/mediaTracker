import SwiftUI
import SwiftData

struct MediaHeaderView: View {
    @Bindable var item: MediaItem
    let themeColor: Color
    let watchProviders: [WatchProviderResult]
    var namespace: Namespace.ID? = nil
    var scrollOffset: CGFloat = 0
    var onStatusChange: ((MediaState?) -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if item.modelContext != nil {
            HStack(alignment: .top, spacing: AppTheme.Spacing.section) {
                PosterView(item: item, themeColor: themeColor, scrollOffset: scrollOffset)
                
                VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    TitleSection(item: item, themeColor: themeColor, watchProviders: watchProviders, onStatusChange: onStatusChange)
                    
                    MetadataSection(item: item, themeColor: themeColor, watchProviders: watchProviders)
                    
                    OverviewSection(overview: item.overview, themeColor: themeColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
