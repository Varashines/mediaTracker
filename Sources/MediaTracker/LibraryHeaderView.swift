import SwiftUI
import SwiftData

struct LibraryHeaderView: View {
    let selectedCategory: NavigationCategory
    let selectedNetworks: [String]?
    let isCategoryPage: Bool
    let isMainSection: Bool
    let appAccent: AppAccent
    let onNetworkSelected: ([String]) -> Void
    var viewModel: MediaViewModel? = nil
    @Query private var collections: [MediaCollection]
    
    var body: some View {
        if let networks = selectedNetworks, let first = networks.first {
            let title = networks.count == 1 ? first : "Merged Studios"
            SectionHeader(title: title, icon: "tv", iconColor: appAccent.color)
                .overlay(alignment: .trailing) {
                    Button { withAnimation { onNetworkSelected([]) } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 40)
                }
        } else if selectedCategory == .upcoming {
            SectionHeader(title: "Queue", icon: "list.bullet.indent", iconColor: .secondary)
                .padding(.bottom, 10)
        } else if !isCategoryPage && !isMainSection && selectedCategory != .discover {
            HStack(spacing: 16) {
                if isSmartCategory {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            viewModel?.selectedCategory = .smartCollections
                        }
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(appAccent.color.opacity(0.8))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .help("Back to Smart Hub")
                }
                
                SectionHeader(title: selectedCategory.title, icon: selectedCategory.icon, iconColor: .secondary)
                    .padding(.horizontal, 0) // Remove internal padding when wrapped
            }
            .padding(.horizontal, 40)
        }
    }
    
    private var isSmartCategory: Bool {
        return selectedCategory == .quickBites || 
               selectedCategory == .catchUp || 
               selectedCategory == .stalled || 
               selectedCategory == .releaseRadar
    }
}
