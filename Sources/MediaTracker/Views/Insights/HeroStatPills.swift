import SwiftUI

struct HeroStatPills: View {
    let stats: LibraryStats

    private var total: Int { stats.totalMovies + stats.totalTVShows }
    private var completed: Int { stats.completedMovies + stats.completedTVShows }
    private var completionRate: Double { total > 0 ? Double(completed) / Double(total) : 0 }

    private var totalMoods: Int {
        stats.moodBreakdown.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        let columns = [
            GridItem(.flexible(), spacing: AppTheme.Spacing.large),
            GridItem(.flexible(), spacing: AppTheme.Spacing.large),
            GridItem(.flexible(), spacing: AppTheme.Spacing.large)
        ]

        LazyVGrid(columns: columns, spacing: AppTheme.Spacing.large) {
            // 1. Stories
            CozyStatCard(
                icon: "popcorn.fill",
                value: "\(total)",
                label: "Stories",
                detail: "\(stats.totalMovies) movies · \(stats.totalTVShows) shows",
                accentColor: .pink
            )
            
            // 2. Time Spent
            CozyStatCard(
                icon: "timer",
                value: formatWatchTimeCompact(minutes: stats.totalWatchTimeMinutes),
                label: "Time Spent",
                detail: "\(stats.totalEpisodesWatched) eps watched",
                accentColor: .orange
            )
            
            // 3. Completion
            CozyStatCard(
                icon: "trophy.fill",
                value: String(format: "%.0f%%", completionRate * 100),
                label: "Completion",
                detail: "\(completed)/\(total) completed",
                accentColor: .teal
            )
            
            // 4. Affinity
            let statsContainer = CategoryStats(
                loved: stats.lovedCount,
                liked: stats.likedCount,
                disliked: stats.dislikedCount,
                total: stats.lovedCount + stats.likedCount + stats.dislikedCount + stats.unratedCount
            )
            let overallAffinity = statsContainer.affinity(cutoff: 1)
            let rated = stats.lovedCount + stats.likedCount + stats.dislikedCount
            CozyStatCard(
                icon: "dna",
                value: String(format: "%.0f%%", overallAffinity * 100),
                label: "Affinity",
                detail: "Based on \(rated) ratings",
                accentColor: .purple
            )

            // 5. Day Streak
            CozyStatCard(
                icon: "flame.fill",
                value: pluralizedDaysLabel(stats.currentStreak),
                label: "Day Streak",
                detail: "Best streak: \(pluralizedDaysLabel(stats.longestStreak))",
                accentColor: .orange
            )

            // 6. Current Vibe
            if !stats.moodBreakdown.isEmpty,
               let top = stats.moodBreakdown.max(by: { $0.percentage < $1.percentage }),
               let topMood = Mood(rawValue: top.name) {
                CozyStatCard(
                    icon: topMood.emoji,
                    value: topMood.rawValue.capitalized,
                    label: "Current Vibe",
                    detail: "\(totalMoods) moods logged",
                    accentColor: .pink
                )
            } else {
                CozyStatCard(
                    icon: "theatermasks.fill",
                    value: "—",
                    label: "Current Vibe",
                    detail: "No moods logged",
                    accentColor: .pink
                )
            }
        }
    }
}

private struct CozyStatCard: View {
    let icon: String
    let value: String
    let label: String
    let detail: String
    let accentColor: Color

    @State private var isHovered = false

    var body: some View {
        GlassCard(color: accentColor, isHovered: isHovered) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                HStack(spacing: AppTheme.Spacing.tiny) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(accentColor)
                    
                    Spacer()
                    
                    Text(detail.uppercased())
                        .font(AppTheme.Font.caption2)
                        .kerning(AppTheme.Kerning.wide)
                        .foregroundStyle(accentColor.opacity(0.85))
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(AppTheme.Font.bodyMedium)
                        .foregroundStyle(.secondary)

                    CountUpText(value: value)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
            .padding(AppTheme.Spacing.medium)
        }
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

func formatWatchTimeCompact(minutes: Int) -> String {
    let days = minutes / 1440
    let hours = (minutes % 1440) / 60
    if days > 0 { return "\(pluralizedDaysLabel(days)) \(pluralizedHoursLabel(hours))" }
    return "\(pluralizedHoursLabel(hours)) \(minutes % 60)m"
}
