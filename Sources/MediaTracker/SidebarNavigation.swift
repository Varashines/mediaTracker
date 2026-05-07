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
            }
            .padding(.vertical, 4)

            Section("My Lists") {
                Label(NavigationCategory.inProgress.title, systemImage: NavigationCategory.inProgress.icon)
                    .tag(SidebarItem.category(.inProgress))
                Label(NavigationCategory.watchlist.title, systemImage: NavigationCategory.watchlist.icon)
                    .tag(SidebarItem.category(.watchlist))
                Label(NavigationCategory.completed.title, systemImage: NavigationCategory.completed.icon)
                    .tag(SidebarItem.category(.completed))
            }
            .padding(.vertical, 4)

            Section("Collections") {
                Label(NavigationCategory.collectionsHub.title, systemImage: NavigationCategory.collectionsHub.icon)
                    .tag(SidebarItem.category(.collectionsHub))
                
                ForEach(pinnedCollections) { collection in
                    Label(collection.name, systemImage: collection.systemImage)
                        .tag(SidebarItem.collection(collection.id, name: collection.name, icon: collection.systemImage))
                }
                
                Label(NavigationCategory.loved.title, systemImage: NavigationCategory.loved.icon)
                    .tag(SidebarItem.category(.loved))
                Label(NavigationCategory.binge.title, systemImage: NavigationCategory.binge.icon)
                    .tag(SidebarItem.category(.binge))
                Label(NavigationCategory.archive.title, systemImage: NavigationCategory.archive.icon)
                    .tag(SidebarItem.category(.archive))
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
    }
}
