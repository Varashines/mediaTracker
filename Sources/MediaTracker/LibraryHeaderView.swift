import SwiftUI
import SwiftData

struct LibraryHeaderView: View {
    let selectedCategory: NavigationCategory
    let selectedNetworks: [String]?
    let isCategoryPage: Bool
    let isMainSection: Bool
    let onNetworkSelected: ([String]) -> Void
    let onBack: (() -> Void)?
    var viewModel: MediaViewModel? = nil
    @Query private var collections: [MediaCollection]

    private var pageTitle: String {
        if let collectionID = viewModel?.selectedCollectionID {
            return collections.first(where: { $0.id == collectionID })?.name ?? selectedCategory.title
        }
        return selectedCategory.title
    }

    private var pageSubtitle: String? {
        switch selectedCategory {
        case .home: return "Welcome back to your theater."
        case .all: return "Exploring your entire cinematic library."
        case .movie: return "Browsing your film collection."
        case .tvShow: return "Tracking your favorite series."
        case .discover: return "Find something new to watch."
        case .smartHub: return "Intelligent library automation."
        case .upcoming: return "Release radar and temporal discovery."
        case .smartUpcoming: return "Tracking the next wave of premieres."
        default: return nil
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1. FILTER INFO
            if let networks = selectedNetworks, let first = networks.first {
                let title = networks.count == 1 ? first : "Merged Studios"
                
                HStack(spacing: 8) {
                    Text("Filtered by:")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                    
                    Button { withAnimation { onNetworkSelected([]) } } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 10)
            }
        }
    }
}
