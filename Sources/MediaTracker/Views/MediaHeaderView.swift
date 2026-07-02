import SwiftUI

struct MediaHeaderView: View {
    let item: MediaItem
    let themeColor: Color
    let watchProviders: [WatchProviderResult]
    var namespace: Namespace.ID? = nil
    var onStatusChange: ((MediaState?) -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if item.modelContext != nil {
            HStack(alignment: .top, spacing: AppTheme.Spacing.section) {
                PosterView(item: item, themeColor: themeColor)
                
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
