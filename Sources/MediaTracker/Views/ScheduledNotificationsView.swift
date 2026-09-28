import SwiftUI
import UserNotifications

/// Shows what the app has actually handed to the notification system.
///
/// The scheduling decisions (which episode, which season finale, how many fit in
/// the system's request budget) were previously unobservable: a pending
/// notification's content can't be read back until it fires, and AppLogger is
/// compiled out of release builds. This is the surface where those choices are
/// visible, which also makes them verifiable without waiting days for a ping.
struct ScheduledNotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var groups: [Group] = []
    @State private var isLoading = true
    @State private var isRescheduling = false

    /// System cap on pending notification requests.
    private static let systemBudget = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if isLoading {
                loadingState
            } else if groups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                        ForEach(groups) { group in
                            groupCard(group)
                        }
                        budgetFooter
                    }
                    .padding(AppTheme.Spacing.medium)
                }
                .background(AppTheme.Colors.background(for: colorScheme))
            }
        }
        .frame(minWidth: 560, minHeight: 460)
        .task { await reload() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.tiny) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scheduled Notifications")
                    .font(AppTheme.Font.settingsRowTitle)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(AppTheme.Font.settingsSubtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isRescheduling {
                ProgressView()
                    .controlSize(.small)
            } else {
                SettingsButton(title: "Reschedule") {
                    Task {
                        isRescheduling = true
                        await NotificationManager.shared.scheduleAllUpcomingNotifications()
                        await reload()
                        isRescheduling = false
                    }
                }
            }
            SettingsButton(title: "Done") { dismiss() }
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.small)
    }

    private var subtitle: String {
        guard !isLoading else { return "Reading the notification queue…" }
        let total = groups.reduce(0) { $0 + $1.items.count }
        if total == 0 { return "Nothing scheduled" }
        return "\(total) of \(Self.systemBudget) system slots used"
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: AppTheme.Spacing.tiny) {
            ProgressView()
            Text("Reading the notification queue…")
                .font(AppTheme.Font.settingsSubtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.tiny) {
            Image(systemName: "bell.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Nothing scheduled")
                .font(AppTheme.Font.settingsRowTitle)
            Text("Enable notifications, then use Reschedule to build the queue from your upcoming titles.")
                .font(AppTheme.Font.settingsSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.large)
    }

    private var budgetFooter: some View {
        HStack(spacing: AppTheme.Spacing.mini) {
            Image(systemName: "info.circle")
                .font(AppTheme.Font.caption2)
            Text("macOS caps pending notifications at \(Self.systemBudget). One alert is scheduled per title, plus season-end and weekly-digest alerts.")
                .font(AppTheme.Font.settingsSubtitle)
                .foregroundStyle(.secondary)
        }
        .padding(.top, AppTheme.Spacing.tiny)
    }

    // MARK: - Group card

    private func groupCard(_ group: Group) -> some View {
        GlassCard(color: .clear, material: .ultraThinMaterial, cornerRadius: AppTheme.Radius.medium) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: AppTheme.Spacing.mini) {
                    Image(systemName: group.kind.symbol)
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(group.kind.tint)
                    Text(group.kind.title)
                        .font(AppTheme.Font.settingsRowTitle)
                    Spacer()
                    Text("\(group.items.count)")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.top, AppTheme.Spacing.small)
                .padding(.bottom, AppTheme.Spacing.mini)

                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    row(item)
                    if index < group.items.count - 1 {
                        Divider().padding(.leading, AppTheme.Spacing.medium)
                    }
                }
            }
            .padding(.bottom, AppTheme.Spacing.mini)
        }
    }

    private func row(_ item: Entry) -> some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.tiny) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(AppTheme.Font.settingsRowTitle)
                    .lineLimit(1)
                Text(item.detail)
                    .font(AppTheme.Font.settingsSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: AppTheme.Spacing.tiny)
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.relativeDay)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.primary)
                Text(item.time)
                    .font(AppTheme.Font.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.mini)
    }

    // MARK: - Data

    private func reload() async {
        isLoading = true
        let requests = await NotificationManager.shared.getPendingNotifications()
        groups = Self.makeGroups(from: requests)
        isLoading = false
    }

    // MARK: - Model

    struct Entry: Identifiable {
        let id: String
        let title: String
        let detail: String
        let date: Date
        var relativeDay: String {
            if Calendar.current.isDateInToday(date) { return "Today" }
            if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
            let days = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: Date()),
                to: Calendar.current.startOfDay(for: date)
            ).day ?? 0
            if days <= 7 { return "In \(days) days" }
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        var time: String {
            date.formatted(.dateTime.hour().minute())
        }
    }

    struct Group: Identifiable {
        let kind: Kind
        var items: [Entry]
        var id: String { kind.title }
    }

    enum Kind: CaseIterable {
        case seasonEnd
        case episode
        case movie
        case digest
        case legacy

        var title: String {
            switch self {
            case .seasonEnd: return "Season Complete"
            case .episode: return "New Episodes"
            case .movie: return "Movie Releases"
            case .digest: return "Weekly Digest"
            case .legacy: return "Older Builds"
            }
        }

        var symbol: String {
            switch self {
            case .seasonEnd: return "checkmark.seal.fill"
            case .episode: return "tv.fill"
            case .movie: return "film.fill"
            case .digest: return "calendar"
            case .legacy: return "clock.badge.exclamationmark"
            }
        }

        @MainActor
        var tint: Color {
            switch self {
            case .seasonEnd: return AppTheme.Colors.accent
            case .episode: return .blue
            case .movie: return .purple
            case .digest: return .orange
            case .legacy: return .secondary
            }
        }

        var order: Int {
            switch self {
            case .seasonEnd: return 0
            case .episode: return 1
            case .movie: return 2
            case .digest: return 3
            case .legacy: return 4
            }
        }
    }

    static func makeGroups(from requests: [UNNotificationRequest]) -> [Group] {
        var buckets: [Kind: [Entry]] = [:]
        for request in requests {
            let content = request.content
            let identifier = request.identifier
            let info = content.userInfo
            let itemType = info["ITEM_TYPE"] as? String
            let season = info["SEASON_NUMBER"] as? Int
            let episode = info["EPISODE_NUMBER"] as? Int
            let date = fireDate(from: request.trigger) ?? .distantFuture

            // Identifiers encode the alert type: the current build schedules a
            // bare "tv-<id>" / "movie-<id>", a season-end alert appends
            // "-seasonend-S<n>", and older builds appended "-day1"/"-day2".
            let kind: Kind
            let detail: String
            if identifier == NotificationManager.weeklyDigestIdentifier || itemType == "weekly_digest" {
                kind = .digest
                detail = content.subtitle ?? "Weekly summary"
            } else if identifier.contains("-seasonend-") {
                kind = .seasonEnd
                detail = content.subtitle ?? "Season finale"
            } else if identifier.hasSuffix("-day1") || identifier.hasSuffix("-day2") {
                kind = .legacy
                detail = content.body ?? "Scheduled by an older build"
            } else if itemType == "movie" {
                kind = .movie
                detail = content.subtitle ?? "Release"
            } else if let season, let episode, episode > 0 {
                kind = .episode
                detail = "S\(season)E\(episode)"
            } else {
                kind = .episode
                detail = content.subtitle ?? "Episode"
            }

            buckets[kind, default: []].append(
                Entry(
                    id: identifier,
                    title: content.title.isEmpty ? identifier : content.title,
                    detail: detail,
                    date: date
                )
            )
        }

        return buckets
            .map { Group(kind: $0.key, items: $0.value.sorted { $0.date < $1.date }) }
            .sorted { $0.kind.order < $1.kind.order }
    }

    static func fireDate(from trigger: UNNotificationTrigger?) -> Date? {
        guard let calendarTrigger = trigger as? UNCalendarNotificationTrigger else { return nil }
        var components = calendarTrigger.dateComponents
        // A trigger with no time set is a day-granularity match.
        if components.hour == nil { components.hour = 9 }
        if components.minute == nil { components.minute = 0 }
        return Calendar.current.date(from: components)
    }
}
