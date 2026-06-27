import SwiftUI
import SwiftData

struct LibrarySummaryBanner: View {
    @State private var stats: Stats?
    
    struct Stats {
        let total: Int
        let movies: Int
        let shows: Int
        let active: Int
        let completed: Int
        let wishlist: Int
    }
    
    var body: some View {
        if let stats {
            HStack(spacing: AppTheme.Spacing.large) {
                statPill(icon: "film", value: stats.movies, label: "Movies")
                statPill(icon: "tv", value: stats.shows, label: "Shows")
                statPill(icon: "play.fill", value: stats.active, label: "Active")
                statPill(icon: "checkmark.circle.fill", value: stats.completed, label: "Done")
                statPill(icon: "heart.fill", value: stats.wishlist, label: "Wishlist")
            }
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
            .task { await loadStats() }
        }
    }
    
    private func statPill(icon: String, value: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(AppTheme.Font.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(AppTheme.Font.bodyBold.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.vertical, AppTheme.Spacing.micro)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(.quaternary, lineWidth: 0.5)
                )
        )
    }
    
    private func loadStats() async {
        let container = try? ModelContainer(for: MediaItem.self, MovieDetails.self, TVShowDetails.self,
                                            TVSeason.self, TVEpisode.self, CastMember.self,
                                            NetworkEntity.self, GenreEntity.self, LanguageEntity.self,
                                            BadgeEntity.self, PersonImageEntity.self,
                                            StudioAliasEntity.self, SearchCacheEntity.self,
                                            MediaCollection.self, ProviderEntity.self)
        guard let container else { return }
        let context = ModelContext(container)
        
        var descriptor = FetchDescriptor<MediaItem>()
        descriptor.propertiesToFetch = [\.typeValue, \.stateValue]
        
        guard let items = try? context.fetch(descriptor) else { return }
        
        var movieCount = 0
        var showCount = 0
        var activeCount = 0
        var completedCount = 0
        var wishlistCount = 0
        
        for item in items {
            if item.typeValue == "Movie" { movieCount += 1 } else { showCount += 1 }
            switch item.stateValue {
            case "Active": activeCount += 1
            case "Completed": completedCount += 1
            case "Wishlist": wishlistCount += 1
            default: break
            }
        }
        
        await MainActor.run {
            self.stats = Stats(
                total: items.count,
                movies: movieCount,
                shows: showCount,
                active: activeCount,
                completed: completedCount,
                wishlist: wishlistCount
            )
        }
    }
}
