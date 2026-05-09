import SwiftUI
import SwiftData

@MainActor
struct SidebarNavigation: View, Equatable {
    @Binding var selection: SidebarItem?
    @Query(filter: #Predicate<MediaCollection> { $0.isPinned }) private var pinnedCollections: [MediaCollection]

    nonisolated static func == (lhs: SidebarNavigation, rhs: SidebarNavigation) -> Bool {
        return lhs._selection.wrappedValue == rhs._selection.wrappedValue
    }

    var body: some View {
        List(selection: $selection) {
            Group {
                Label(NavigationCategory.home.title, systemImage: NavigationCategory.home.icon)
                    .tag(SidebarItem.category(.home))

                Label(NavigationCategory.discover.title, systemImage: NavigationCategory.discover.icon)
                    .tag(SidebarItem.category(.discover))

                Label(NavigationCategory.upcoming.title, systemImage: NavigationCategory.upcoming.icon)
                    .tag(SidebarItem.category(.upcoming))
            }
            .padding(.vertical, 4)

            Section("Library") {
                Label(NavigationCategory.all.title, systemImage: NavigationCategory.all.icon)
                    .tag(SidebarItem.category(.all))
                Label(NavigationCategory.movie.title, systemImage: NavigationCategory.movie.icon)
                    .tag(SidebarItem.category(.movie))
                Label(NavigationCategory.tvShow.title, systemImage: NavigationCategory.tvShow.icon)
                    .tag(SidebarItem.category(.tvShow))
                
                Label(NavigationCategory.smartHub.title, systemImage: NavigationCategory.smartHub.icon)
                    .tag(SidebarItem.category(.smartHub))

                ForEach(pinnedCollections) { collection in
                    Label(collection.name, systemImage: collection.systemImage)
                        .tag(SidebarItem.collection(collection.id, name: collection.name, icon: collection.systemImage))
                }
            }
            .padding(.vertical, 4)
            
            Section("Analytics") {
                Label(NavigationCategory.insights.title, systemImage: NavigationCategory.insights.icon)
                    .tag(SidebarItem.category(.insights))
            }
            .padding(.vertical, 4)

            Section("Configuration") {
                Label(NavigationCategory.settings.title, systemImage: NavigationCategory.settings.icon)
                    .tag(SidebarItem.category(.settings))
            }
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
