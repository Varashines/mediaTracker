import SwiftUI

@MainActor
struct SidebarNavigation: View, Equatable {
    @Binding var selection: NavigationCategory?

    nonisolated static func == (lhs: SidebarNavigation, rhs: SidebarNavigation) -> Bool {
        return lhs._selection.wrappedValue == rhs._selection.wrappedValue
    }

    var body: some View {
        List(selection: $selection) {
            Group {
                Label(NavigationCategory.home.title, systemImage: NavigationCategory.home.icon)
                    .tag(NavigationCategory.home)

                Label(NavigationCategory.discover.title, systemImage: NavigationCategory.discover.icon)
                    .tag(NavigationCategory.discover)

                Label(NavigationCategory.upcoming.title, systemImage: NavigationCategory.upcoming.icon)
                    .tag(NavigationCategory.upcoming)
            }
            .padding(.vertical, 4)

            Section("Library") {
                Label(NavigationCategory.all.title, systemImage: NavigationCategory.all.icon)
                    .tag(NavigationCategory.all)
                Label(NavigationCategory.movie.title, systemImage: NavigationCategory.movie.icon)
                    .tag(NavigationCategory.movie)
                Label(NavigationCategory.tvShow.title, systemImage: NavigationCategory.tvShow.icon)
                    .tag(NavigationCategory.tvShow)
            }
            .padding(.vertical, 4)

            Section("My Lists") {
                Label(NavigationCategory.inProgress.title, systemImage: NavigationCategory.inProgress.icon)
                    .tag(NavigationCategory.inProgress)
                Label(NavigationCategory.watchlist.title, systemImage: NavigationCategory.watchlist.icon)
                    .tag(NavigationCategory.watchlist)
                Label(NavigationCategory.completed.title, systemImage: NavigationCategory.completed.icon)
                    .tag(NavigationCategory.completed)
            }
            .padding(.vertical, 4)

            Section("Collections") {
                Label(NavigationCategory.collectionsHub.title, systemImage: NavigationCategory.collectionsHub.icon)
                    .tag(NavigationCategory.collectionsHub)
                Label(NavigationCategory.loved.title, systemImage: NavigationCategory.loved.icon)
                    .tag(NavigationCategory.loved)
                Label(NavigationCategory.binge.title, systemImage: NavigationCategory.binge.icon)
                    .tag(NavigationCategory.binge)
                Label(NavigationCategory.archive.title, systemImage: NavigationCategory.archive.icon)
                    .tag(NavigationCategory.archive)
            }
            .padding(.vertical, 4)
            
            Section("Analytics") {
                Label(NavigationCategory.insights.title, systemImage: NavigationCategory.insights.icon)
                    .tag(NavigationCategory.insights)
            }
            .padding(.vertical, 4)

            Section("Configuration") {
                Label(NavigationCategory.settings.title, systemImage: NavigationCategory.settings.icon)
                    .tag(NavigationCategory.settings)
            }
            .padding(.vertical, 4)
        }
    }
}
