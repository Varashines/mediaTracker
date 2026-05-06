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
        if let collectionID = viewModel?.selectedCollectionID,
           let collection = collections.first(where: { $0.id == collectionID }) {
            HStack(spacing: 12) {
                Button {
                    withAnimation {
                        viewModel?.selectedCollectionID = nil
                        viewModel?.filterSubject.send()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.bold())
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)

                SectionHeader(title: collection.name, icon: collection.systemImage, iconColor: appAccent.color)
            }
        } else if let networks = selectedNetworks, let first = networks.first {
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
            SectionHeader(title: selectedCategory.title, icon: selectedCategory.icon, iconColor: .secondary)
        }
    }
}
