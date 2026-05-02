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
        if item.modelContext != nil && !item.isDeleted {
            HStack(alignment: .center, spacing: 30) {
                PosterView(item: item, themeColor: themeColor, namespace: namespace)
                
                VStack(alignment: .leading, spacing: 20) {
                    TitleSection(item: item, themeColor: themeColor, onStatusChange: onStatusChange, namespace: namespace)
                    
                    if item.isUpcoming, let badgeText = item.detailBadgeText {
                        let isAvailable = badgeText.contains("Streaming") || badgeText.contains("Available")
                        
                        HStack(spacing: 8) {
                            Image(systemName: isAvailable ? "play.fill" : "sparkles")
                                .font(.system(size: 14, weight: .black))
                                .symbolEffect(.pulse, options: .repeating, value: isAvailable)
                                .foregroundStyle(isAvailable ? .white : .yellow)
                            
                            Text(badgeText)
                                .font(.headline)
                        }
                        .liquidGlassPill(
                            accentColor: isAvailable ? Color.semanticGreen(for: colorScheme) : themeColor,
                            isSolid: isAvailable
                        )
                        .padding(.top, 4)
                    }
                    
                    MetadataSection(item: item, themeColor: themeColor)
                    
                    OverviewSection(overview: item.overview)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
