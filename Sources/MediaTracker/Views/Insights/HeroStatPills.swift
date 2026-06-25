import SwiftUI

struct HeroStatPills: View {
    let stats: LibraryStats

    var body: some View {
        let total = stats.totalMovies + stats.totalTVShows
        let completed = stats.completedMovies + stats.completedTVShows
        let completionRate = total > 0 ? Double(completed) / Double(total) : 0

        LazyVGrid(columns: [GridItem(.flexible(), spacing: AppTheme.Spacing.large), GridItem(.flexible(), spacing: AppTheme.Spacing.large)], spacing: AppTheme.Spacing.large) {
            StatPill(
                icon: "film.stack.fill",
                value: "\(total)",
                label: "Stories",
                detail: "\(stats.totalMovies) movies · \(stats.totalTVShows) shows",
                color: .pink
            )
            StatPill(
                icon: "clock.fill",
                value: formatWatchTimeCompact(minutes: stats.totalWatchTimeMinutes),
                label: "Time Well Spent",
                detail: "\(stats.totalEpisodesWatched) episodes devoured",
                color: .orange
            )
            StatPill(
                icon: "checkmark.circle.fill",
                value: String(format: "%.0f%%", completionRate * 100),
                label: "The Finish Line",
                detail: "\(completed)/\(total) completed",
                color: .teal
            )
            StatPill(
                icon: "tv.inset.filled",
                value: "\(stats.totalEpisodesWatched)",
                label: "Episodes",
                detail: "Watched across all shows",
                color: .purple
            )
        }
    }
}

struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    let detail: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.tiny) {
                Image(systemName: icon)
                    .font(AppTheme.Font.title3)
                    .foregroundStyle(color)
                Text(label.uppercased())
                    .font(AppTheme.Font.caption)
                    .kerning(AppTheme.Kerning.wide)
                    .foregroundStyle(color.opacity(0.7))
            }

            CountUpText(value: value)
                .font(AppTheme.Font.titleLarge)
                .foregroundStyle(.primary)

            Text(detail)
                .font(AppTheme.Font.label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .fill(AppTheme.Colors.cardFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(color.opacity(colorScheme == .dark ? 0.15 : 0.1), lineWidth: 0.5)
        )
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(color.opacity(colorScheme == .dark ? 0.06 : 0.04))
                .offset(x: 8, y: 4)
                .allowsHitTesting(false)
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.06 : 0), radius: 8, y: isHovered ? 4 : 0)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.springSnappy) { isHovered = hovering }
        }
    }
}

func formatWatchTimeCompact(minutes: Int) -> String {
    let days = minutes / 1440
    let hours = (minutes % 1440) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    return "\(hours)h \(minutes % 60)m"
}
