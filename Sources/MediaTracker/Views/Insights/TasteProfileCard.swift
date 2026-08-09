import SwiftUI
import SwiftData

/// Taste Profile content — two side-by-side sections:
/// preference rows (left) and rating donut + legend (right).
/// The surrounding card container is provided by `InsightsSectionCard`.
struct TasteProfileCard: View {
    let stats: LibraryStats
    @Environment(\.modelContext) private var modelContext

    @Query private var networkEntities: [NetworkEntity]

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
