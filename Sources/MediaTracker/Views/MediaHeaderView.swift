import SwiftUI

struct MediaHeaderView: View {
    let item: MediaItem
    let themeColor: Color
    let watchProviders: [WatchProviderResult]
    var namespace: Namespace.ID? = nil
    var onStatusChange: ((MediaState?) -> Void)? = nil
    var posterOptions: [String] = []
    var isCustomPoster: Bool = false
    var onSelectPoster: ((String) -> Void)? = nil
    var onResetPoster: (() -> Void)? = nil
    var logoOptions: [String] = []
    var isCustomLogo: Bool = false
    var onSelectLogo: ((String) -> Void)? = nil
    var onResetLogo: (() -> Void)? = nil
    var onMoodChanged: ((Mood?) -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if item.modelContext != nil {
            HStack(alignment: .top, spacing: AppTheme.Spacing.section) {
                PosterView(
                    item: item,
                    themeColor: themeColor,
                    posterOptions: posterOptions,
                    isCustomPoster: isCustomPoster,
                    onSelectPoster: onSelectPoster,
                    onResetPoster: onResetPoster
                )
                
                VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    TitleSection(
                        item: item,
                        themeColor: themeColor,
                        watchProviders: watchProviders,
                        onStatusChange: onStatusChange,
                        logoOptions: logoOptions,
                        isCustomLogo: isCustomLogo,
                        onSelectLogo: onSelectLogo,
                        onResetLogo: onResetLogo,
                        onMoodChanged: onMoodChanged
                    )
                    
                    MetadataSection(item: item, themeColor: themeColor, watchProviders: watchProviders)
                    
                    OverviewSection(overview: item.overview, themeColor: themeColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
