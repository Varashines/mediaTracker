import SwiftUI
import SwiftData

@MainActor
struct SidebarNavigation: View {
    @Binding var selection: SidebarItem?
    @Query(filter: #Predicate<MediaCollection> { $0.isPinned }) private var pinnedCollections: [MediaCollection]
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    @AppStorage("pinned_system_categories") private var pinnedSystemCategories: String = ""
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var sidebarNamespace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                // Main Section
                VStack(alignment: .leading, spacing: 4) {
                    sidebarRow(title: NavigationCategory.upcoming.title, icon: NavigationCategory.upcoming.icon, item: .category(.upcoming))
                    sidebarRow(title: "Now Watching", icon: "play.fill", item: .category(.home))
                    sidebarRow(title: NavigationCategory.inProgress.title, icon: NavigationCategory.inProgress.icon, item: .category(.inProgress))
                    sidebarRow(title: NavigationCategory.watchlist.title, icon: NavigationCategory.watchlist.icon, item: .category(.watchlist))
                    sidebarRow(title: NavigationCategory.all.title, icon: NavigationCategory.all.icon, item: .category(.all))
                }
                .padding(.bottom, 16)

                sidebarSectionHeader("Smart Folders")
                VStack(alignment: .leading, spacing: 4) {
                    sidebarRow(title: NavigationCategory.stalled.title, icon: NavigationCategory.stalled.icon, item: .category(.stalled))
                    sidebarRow(title: "Dropped", icon: "xmark.bin", item: .category(.disliked))
                    sidebarRow(title: NavigationCategory.archive.title, icon: NavigationCategory.archive.icon, item: .category(.archive))
                }
                .padding(.bottom, 16)
                
                sidebarSectionHeader("Explore")
                VStack(alignment: .leading, spacing: 4) {
                    sidebarRow(title: NavigationCategory.discover.title, icon: NavigationCategory.discover.icon, item: .category(.discover))
                }
                .padding(.bottom, 16)
                
                sidebarSectionHeader("Categories")
                VStack(alignment: .leading, spacing: 4) {
                    sidebarRow(title: NavigationCategory.movie.title, icon: NavigationCategory.movie.icon, item: .category(.movie))
                    sidebarRow(title: NavigationCategory.tvShow.title, icon: NavigationCategory.tvShow.icon, item: .category(.tvShow))
                    
                    let pinnedList = pinnedSystemCategories.split(separator: ",").map(String.init)
                    ForEach(NavigationCategory.allCases.filter { pinnedList.contains($0.rawValue) }) { category in
                        sidebarRow(title: category.title, icon: category.icon, item: .category(category))
                    }
                    
                    ForEach(pinnedCollections) { collection in
                        sidebarRow(title: collection.name, icon: collection.systemImage, item: .collection(collection.id, name: collection.name, icon: collection.systemImage))
                    }
                }
                .padding(.bottom, 16)
                
                sidebarSectionHeader("Analytics")
                sidebarRow(title: NavigationCategory.insights.title, icon: NavigationCategory.insights.icon, item: .category(.insights))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 16)
        }
    }

    private func sidebarRow(title: String, icon: String, item: SidebarItem) -> some View {
        let isSelected = selection == item
        
        // Only append .fill if the icon name doesn't already contain it and it's a standard symbol
        let iconName: String
        if isSelected {
            if icon.contains(".fill") || icon == "calendar" || icon == "cpu" || icon == "sparkles" {
                iconName = icon
            } else {
                iconName = "\(icon).fill"
            }
        } else {
            iconName = icon
        }
        
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selection = item
            }
            FeedbackManager.shared.trigger(.click)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .white : Color.primary.opacity(0.6))
                    .frame(width: 24)
                
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : Color.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.blue)
                        .matchedGeometryEffect(id: "sidebar_active", in: sidebarNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary.opacity(0.7))
            .padding(.leading, 12)
            .padding(.bottom, 4)
    }
}
