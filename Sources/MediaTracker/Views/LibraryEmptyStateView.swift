import SwiftUI

struct LibraryEmptyStateView: View {
    let title: String
    var icon: String = "tray"
    var description: String = ""
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    init(category: NavigationCategory, onExplore: (() -> Void)? = nil) {
        self.title = Self.title(for: category)
        self.icon = Self.icon(for: category)
        self.description = Self.description(for: category)
        self.actionLabel = onExplore != nil ? "Explore Discovery Hub" : nil
        self.action = onExplore
    }

    init(title: String, icon: String = "tray", description: String = "", actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.icon = icon
        self.description = description
        self.actionLabel = actionLabel
        self.action = action
    }

    var body: some View {
        VStack {
            ContentUnavailableView {
                Label(title, systemImage: icon)
            } description: {
                if !description.isEmpty {
                    Text(description)
                }
            } actions: {
                if let actionLabel, let action {
                    Button(action: action) {
                        Text(actionLabel)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(AppTheme.Colors.accent)
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

    private static func title(for category: NavigationCategory) -> String {
        switch category {
        case .upcoming: "Nothing Upcoming"
        case .inProgress: "Nothing in Progress"
        case .watchlist: "Watchlist is Empty"
        case .loved: "No Loved Items"
        case .completed: "Nothing Completed"
        case .archive: "Archive is Empty"
        case .disliked: "No Disliked Items"
        default: "Library is Empty"
        }
    }

    private static func icon(for category: NavigationCategory) -> String {
        switch category {
        case .upcoming: "calendar.badge.clock"
        case .inProgress: "play.slash"
        case .watchlist: "list.bullet.rectangle"
        case .loved: "heart.fill"
        case .completed: "checkmark.circle.fill"
        case .archive: "archivebox"
        case .disliked: "hand.thumbsdown.fill"
        default: "tray"
        }
    }

    private static func description(for category: NavigationCategory) -> String {
        switch category {
        case .upcoming: "No releases or new episodes are expected soon."
        case .inProgress: "You're all caught up! Start something new from your watchlist."
        case .watchlist: "Your watchlist is empty. Search for something to add!"
        case .loved: "Items you've loved will appear here."
        case .completed: "All your finished movies and series will be collected here."
        case .archive: "Items you've paused or dropped will appear here."
        case .disliked: "Items you've actively disliked."
        default: "Start building your collection by searching for movies or shows."
        }
    }
}
