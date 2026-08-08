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

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.accent.opacity(0.12))
                    .frame(width: 72, height: 72)
                
                Image(systemName: icon)
                    .font(AppTheme.Font.title)
                    .foregroundStyle(AppTheme.Colors.accent)
            }

            VStack(spacing: AppTheme.Spacing.tiny) {
                Text(title)
                    .font(AppTheme.Font.title3)
                    .foregroundStyle(.primary)
                
                if !description.isEmpty {
                    Text(description)
                        .font(AppTheme.Font.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }

                if !APIClient.shared.isTMDBConfigured {
                    Text("Connect an API key in Settings → Services to start tracking media")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }

            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(AppTheme.Font.bodyBold)
                        .foregroundStyle(AppTheme.Colors.accent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(AppTheme.Colors.accent.opacity(0.15))
                        )
                        .overlay(
                            Capsule()
                                .stroke(AppTheme.Colors.accent.opacity(0.3), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.interactive)
                .hoverScaled(.subtle)
            }
        }
        .padding(AppTheme.Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func title(for category: NavigationCategory) -> String {
        switch category {
        case .upcoming: "Nothing Upcoming"
        case .inProgress: "Nothing in Progress"
        case .watchlist: "Watchlist is Empty"
        case .loved: "No Loved Items"
        case .completed: "Nothing Completed"
        case .archive: "Shelved is Empty"
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
        case .archive: "Items you've shelved will appear here."
        case .disliked: "Items you've actively disliked."
        default: "Start building your collection by searching for movies or shows."
        }
    }
}
