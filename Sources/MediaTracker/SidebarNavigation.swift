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

                Label(NavigationCategory.upcoming.title, systemImage: NavigationCategory.upcoming.icon)
                    .tag(NavigationCategory.upcoming)

                Label(NavigationCategory.inProgress.title, systemImage: NavigationCategory.inProgress.icon)
                    .tag(NavigationCategory.inProgress)

                Label(NavigationCategory.watchlist.title, systemImage: NavigationCategory.watchlist.icon)
                    .tag(NavigationCategory.watchlist)

                Label(NavigationCategory.all.title, systemImage: NavigationCategory.all.icon)
                    .tag(NavigationCategory.all)
            }
            .padding(.vertical, 4)

            Section("Smart Folders") {
                Label(NavigationCategory.loved.title, systemImage: NavigationCategory.loved.icon)
                    .tag(NavigationCategory.loved)
                Label(NavigationCategory.completed.title, systemImage: NavigationCategory.completed.icon)
                    .tag(NavigationCategory.completed)
                Label(NavigationCategory.archive.title, systemImage: NavigationCategory.archive.icon)
                    .tag(NavigationCategory.archive)
                Label(NavigationCategory.disliked.title, systemImage: NavigationCategory.disliked.icon)
                    .tag(NavigationCategory.disliked)
                Label(NavigationCategory.binge.title, systemImage: NavigationCategory.binge.icon)
                    .tag(NavigationCategory.binge)
            }
            .padding(.vertical, 4)
            
            Section("Explore") {
                Label(NavigationCategory.discover.title, systemImage: NavigationCategory.discover.icon)
                    .tag(NavigationCategory.discover)
                
                Label(NavigationCategory.insights.title, systemImage: NavigationCategory.insights.icon)
                    .tag(NavigationCategory.insights)
            }
            .padding(.vertical, 4)
            
            Section("Categories") {
                ForEach([NavigationCategory.movie, NavigationCategory.tvShow], id: \.self) { cat in
                    Label(cat.title, systemImage: cat.icon)
                        .tag(cat)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
