import SwiftUI

@MainActor
struct SidebarNavigation: View, Equatable {
    @Binding var selection: String?

    nonisolated static func == (lhs: SidebarNavigation, rhs: SidebarNavigation) -> Bool {
        return lhs._selection.wrappedValue == rhs._selection.wrappedValue
    }

    var body: some View {
        List(selection: $selection) {
            Group {
                Label("Home", systemImage: "house.fill")
                    .tag("Home")

                Label("Upcoming", systemImage: "calendar")
                    .tag("Upcoming")

                Label("In Progress", systemImage: "play.circle")
                    .tag("InProgress")

                Label("Watchlist", systemImage: "list.bullet.rectangle")
                    .tag("Watchlist")

                Label("Library", systemImage: "tray.full")
                    .tag("All")
            }
            .padding(.vertical, 4)

            Section("Smart Folders") {
                Label("Loved", systemImage: "heart.fill")
                    .tag("Loved")
                Label("Completed", systemImage: "checkmark.circle.fill")
                    .tag("Completed")
                Label("Archive", systemImage: "archivebox")
                    .tag("Archive")
                Label("Disliked", systemImage: "hand.thumbsdown.fill")
                    .tag("Disliked")
                Label("Binge", systemImage: "rectangle.stack.fill")
                    .tag("Binge")
            }
            .padding(.vertical, 4)
            
            Section("Explore") {
                Label("Discovery Hub", systemImage: "sparkles.tv")
                    .tag("Discover")
                
                Label("Insights", systemImage: "chart.bar.xaxis")
                    .tag("Insights")
            }
            .padding(.vertical, 4)
            
            Section("Categories") {
                ForEach(MediaType.allCases, id: \.self) { type in
                    let name = type.pluralName
                    let img = icon(for: type)
                    Label(name, systemImage: img)
                        .tag(type.rawValue)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func icon(for type: MediaType) -> String {
        switch type {
        case .movie: return "film"
        case .tvShow: return "tv"
        }
    }
}
