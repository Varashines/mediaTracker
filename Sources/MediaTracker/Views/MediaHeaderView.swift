import SwiftUI
import SwiftData

struct MediaHeaderView: View {
    @Bindable var item: MediaItem
    let themeColor: Color
    var viewModel: DetailViewModel? = nil
    var namespace: Namespace.ID? = nil
    var onStatusChange: ((MediaState?) -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if item.modelContext != nil {
            HStack(alignment: .top, spacing: AppTheme.Spacing.section) {
                PosterView(item: item, themeColor: themeColor, namespace: namespace)
                
                VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    TitleSection(item: item, themeColor: themeColor, onStatusChange: onStatusChange, namespace: namespace)
                    
                    MetadataSection(item: item, themeColor: themeColor)
                    
                    OverviewSection(overview: item.overview, themeColor: themeColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
