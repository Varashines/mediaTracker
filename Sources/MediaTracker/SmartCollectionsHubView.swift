import SwiftUI
import SwiftData

struct SmartCollectionsHubView: View {
    let namespace: Namespace.ID
    @Binding var selection: SidebarItem?
    
    @Environment(\.modelContext) private var modelContext
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    
    @State private var counts: [NavigationCategory: Int] = [:]
    
    private let smartCategories: [NavigationCategory] = [
        .releaseRadar, .catchUp, .quickBites, .stalled
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 35) {
                // Grid of Smart Cards
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 25)], spacing: 25) {
                    ForEach(smartCategories) { category in
                        SmartCollectionCard(
                            category: category,
                            count: counts[category] ?? 0,
                            accentColor: appAccent.color
                        ) {
                            selection = .category(category)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 40)
                
                Spacer(minLength: 50)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .task {
            await fetchCounts()
        }
    }
    
    private func fetchCounts() async {
        let actor = MediaFilterActor(modelContainer: modelContext.container)
        var newCounts: [NavigationCategory: Int] = [:]
        
        for cat in smartCategories {
            do {
                let result = try await actor.filterAndSort(
                    category: cat,
                    searchText: "",
                    sortOrder: .alphabetical,
                    network: nil,
                    language: nil,
                    limit: 1,
                    offset: 0
                )
                newCounts[cat] = result.totalCount
            } catch {
                print("Error fetching count for \(cat.rawValue): \(error)")
            }
        }
        
        await MainActor.run {
            withAnimation(.smooth) {
                self.counts = newCounts
            }
        }
    }
}

private struct SmartCollectionCard: View {
    let category: NavigationCategory
    let count: Int
    let accentColor: Color
    let action: () -> Void
    
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Image(systemName: category.icon)
                        .font(.title)
                        .foregroundStyle(accentColor)
                        .frame(width: 50, height: 50)
                        .background(accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    Spacer()
                    
                    Text("\(count)")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.title)
                        .font(.headline)
                    
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.03 : 0.02))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.primary.opacity(isHovered ? 0.1 : 0.05), lineWidth: 1)
                    }
            }
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
    
    private var description: String {
        switch category {
        case .releaseRadar: return "Recently released episodes and movies from your library."
        case .catchUp: return "Shows with backlogs and new episodes airing this week."
        case .quickBites: return "Short media under 90 minutes for quick viewing."
        case .stalled: return "Active titles with no progress in the last 3 months."
        default: return ""
        }
    }
}
