import SwiftUI
import SwiftData

struct LibraryHeaderView: View {
    let selectedCategory: NavigationCategory
    let selectedNetworks: [String]?
    let isCategoryPage: Bool
    let onNetworkSelected: ([String]) -> Void
    let onBack: (() -> Void)?
    var viewModel: MediaViewModel? = nil
    
    @State private var collectionName: String? = nil

    var pageTitle: String {
        if viewModel?.collection.selectedCollectionID != nil {
            return collectionName ?? selectedCategory.title
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
            // Page title
            HStack(spacing: AppTheme.Spacing.small) {
                Text(pageTitle)
                    .font(AppTheme.Font.title)
                    .foregroundStyle(.primary)

                Spacer()
            }

            // Page subtitle
            if let subtitle = pageSubtitle {
                Text(subtitle)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
            }

            // Network filter badge
            if let networks = selectedNetworks, let first = networks.first {
                let title = networks.count == 1 ? first : "Merged Studios"

                HStack(spacing: AppTheme.Spacing.tiny) {
                    Text("Filtered by:")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)

                    Text(title)
                        .font(AppTheme.Font.caption.weight(.bold))
                        .foregroundStyle(AppTheme.Colors.accent)

                    Button { withAnimation(AppTheme.Animation.springSnappy) { onNetworkSelected([]) } } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppTheme.Icon.medium)
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
        .task(id: viewModel?.collection.selectedCollectionID) {
            guard let collectionID = viewModel?.collection.selectedCollectionID else {
                collectionName = nil
                return
            }
            let descriptor = FetchDescriptor<MediaCollection>(
                predicate: #Predicate { $0.id == collectionID },
                sortBy: [SortDescriptor(\.name)]
            )
            collectionName = try? modelContext.fetch(descriptor).first?.name
        }
    }
    
    @Environment(\.modelContext) private var modelContext
}
