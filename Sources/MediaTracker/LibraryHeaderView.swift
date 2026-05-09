import SwiftUI
import SwiftData

struct LibraryHeaderView: View {
    let selectedCategory: NavigationCategory
    let selectedNetworks: [String]?
    let isCategoryPage: Bool
    let isMainSection: Bool
    let appAccent: AppAccent
    let onNetworkSelected: ([String]) -> Void
    let onBack: (() -> Void)?
    var viewModel: MediaViewModel? = nil
    @Query private var collections: [MediaCollection]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let networks = selectedNetworks, let first = networks.first {
                let title = networks.count == 1 ? first : "Merged Studios"
                
                HStack(spacing: 8) {
                    Text("Filtered by:")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    Text(title)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(appAccent.color)
                    
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
