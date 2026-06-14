import SwiftUI

struct HeroStatPills: View {
    let stats: LibraryStats

    var body: some View {
        let total = stats.totalMovies + stats.totalTVShows
        let completed = stats.completedMovies + stats.completedTVShows
        let completionRate = total > 0 ? Double(completed) / Double(total) : 0

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(color.opacity(0.7))
            }

            CountUpText(value: value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(detail)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 180, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                .fill(color.opacity(colorScheme == .dark ? 0.08 : 0.04))
        )
    }
}

func formatWatchTimeCompact(minutes: Int) -> String {
    let days = minutes / 1440
    let hours = (minutes % 1440) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    return "\(hours)h \(minutes % 60)m"
}
