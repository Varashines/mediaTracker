import SwiftUI
import SwiftData

/// Taste Profile content — two side-by-side sections:
/// preference rows (left) and rating donut + legend (right).
/// The surrounding card container is provided by `InsightsSectionCard`.
struct TasteProfileCard: View {
    let stats: LibraryStats
    @Environment(\.modelContext) private var modelContext

    // Bounded: only networks actually used by library items, capped — the
    // unbounded variant fetched every row and invalidated the card on any change.
    @Query private var networkEntities: [NetworkEntity]

    init(stats: LibraryStats) {
        self.stats = stats
        var descriptor = FetchDescriptor<NetworkEntity>(
            predicate: #Predicate { $0.count > 0 },
            sortBy: [SortDescriptor(\.count, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        _networkEntities = Query(descriptor)
    }

    private var topNetworkName: String { stats.topRatedNetworks.first?.name ?? "—" }
    private var topStudioName:  String { stats.topRatedStudios.first?.name  ?? "—" }

    private var topNetworkLogoPath: String? {
        networkEntities.first(where: { $0.name.lowercased() == topNetworkName.lowercased() })?.logoPath
    }
    private var topStudioLogoPath: String? {
        networkEntities.first(where: { $0.name.lowercased() == topStudioName.lowercased() })?.logoPath
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.large) {
            TastePreferenceSection(
                stats: stats,
                topNetworkName: topNetworkName,
                topStudioName: topStudioName,
                topNetworkLogoPath: topNetworkLogoPath,
                topStudioLogoPath: topStudioLogoPath
            )

            TasteRatingSection(stats: stats)
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
        .frame(maxWidth: .infinity)
    }
}
