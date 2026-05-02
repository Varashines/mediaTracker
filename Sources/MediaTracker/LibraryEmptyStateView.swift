import SwiftUI

struct LibraryEmptyStateView: View {
    let category: NavigationCategory
    var onExplore: (() -> Void)? = nil

    var body: some View {
        VStack {
            ContentUnavailableView {
                Label(title, systemImage: icon)
            } description: {
                Text(description)
            } actions: {
                if let onExplore = onExplore {
                    Button(action: onExplore) {
                        Text("Explore Discovery Hub")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.interactive)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.top, 100)
    }

    private var title: String {
        switch category {
        case .upcoming: return "Nothing Upcoming"
        case .inProgress: return "Nothing in Progress"
        case .watchlist: return "Watchlist is Empty"
        case .loved: return "No Loved Items"
        case .completed: return "Nothing Completed"
        case .archive: return "Archive is Empty"
        case .disliked: return "No Disliked Items"
        default: return "Library is Empty"
        }
    }

    private var icon: String {
        switch category {
        case .upcoming: return "calendar.badge.clock"
        case .inProgress: return "play.slash"
        case .watchlist: return "list.bullet.rectangle"
        case .loved: return "heart.fill"
        case .completed: return "checkmark.circle.fill"
        case .archive: return "archivebox"
        case .disliked: return "hand.thumbsdown.fill"
        default: return "tray"
        }
    }

    private var description: String {
        switch category {
        case .upcoming: return "No releases or new episodes are expected soon."
        case .inProgress: return "You're all caught up! Start something new from your watchlist."
        case .watchlist: return "Your watchlist is empty. Search for something to add!"
        case .loved: return "Items you've loved will appear here."
        case .completed: return "All your finished movies and series will be collected here."
        case .archive: return "Items you've paused or dropped will appear here."
        case .disliked: return "Items you've actively disliked."
        default: return "Start building your collection by searching for movies or shows."
        }
    }
}
