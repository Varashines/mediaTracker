import SwiftUI

struct HeroStatPills: View {
    let stats: LibraryStats

    var body: some View {
        let total = stats.totalMovies + stats.totalTVShows
        let completed = stats.completedMovies + stats.completedTVShows
        let completionRate = total > 0 ? Double(completed) / Double(total) : 0

        let statsContainer = CategoryStats(
            loved: stats.lovedCount,
            liked: stats.likedCount,
            disliked: stats.dislikedCount,
            total: stats.lovedCount + stats.likedCount + stats.dislikedCount + stats.unratedCount,
            ratedTitles: stats.lovedCount + stats.likedCount + stats.dislikedCount
        )
        let overallAffinity = statsContainer.affinity(cutoff: 1)

        let pillWidth: CGFloat = 240
        let totalWidth = pillWidth * 4 + AppTheme.Spacing.large * 3 + AppTheme.Spacing.pageMargin * 2
        let contentHeight = 86 + AppTheme.Spacing.medium * 2

        GeometryReader { geo in
            if geo.size.width >= totalWidth {
                // Centered layout when content fits
                HStack(spacing: AppTheme.Spacing.large) {
                    ClaymorphicHeroCard(
                        emoji: "🍿",
                        value: "\(total)",
                        label: "Titles",
                        detail: "\(stats.totalMovies) 🎬 · \(stats.totalTVShows) 📺",
                        color: .pink
                    )
                    ClaymorphicHeroCard(
                        emoji: "⏱️",
                        value: formatWatchTimeCompact(minutes: stats.totalWatchTimeMinutes),
                        label: "Watch Time",
                        detail: "\(stats.totalEpisodesWatched) eps",
                        color: .orange
                    )
                    ClaymorphicHeroCard(
                        emoji: "🏆",
                        value: String(format: "%.0f%%", completionRate * 100),
                        label: "Completion",
                        detail: "\(completed)/\(total)",
                        color: .teal
                    )
                    ClaymorphicHeroCard(
                        emoji: "💖",
                        value: String(format: "%.0f%%", overallAffinity * 100),
                        label: "Affinity",
                        detail: "\(stats.lovedCount)❤️ · \(stats.likedCount)👍 · \(stats.dislikedCount)👎",
                        color: .purple
                    )
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, AppTheme.Spacing.medium)
            } else {
                // Scrollable fallback when content overflows
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.large) {
                        ClaymorphicHeroCard(
                            emoji: "🍿",
                            value: "\(total)",
                            label: "Titles",
                            detail: "\(stats.totalMovies) 🎬 · \(stats.totalTVShows) 📺",
                            color: .pink
                        )
                        ClaymorphicHeroCard(
                            emoji: "⏱️",
                            value: formatWatchTimeCompact(minutes: stats.totalWatchTimeMinutes),
                            label: "Watch Time",
                            detail: "\(stats.totalEpisodesWatched) eps",
                            color: .orange
                        )
                        ClaymorphicHeroCard(
                            emoji: "🏆",
                            value: String(format: "%.0f%%", completionRate * 100),
                            label: "Completion",
                            detail: "\(completed)/\(total)",
                            color: .teal
                        )
                        ClaymorphicHeroCard(
                            emoji: "💖",
                            value: String(format: "%.0f%%", overallAffinity * 100),
                            label: "Affinity",
                            detail: "\(stats.lovedCount)❤️ · \(stats.likedCount)👍 · \(stats.dislikedCount)👎",
                            color: .purple
                        )
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .padding(.vertical, AppTheme.Spacing.medium)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(height: contentHeight)
    }
}

// MARK: - Claymorphic Card

private struct ClaymorphicCard: View {
    let color: Color
    let isHovered: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            // 3D Puffed background color
            .fill(
                LinearGradient(
                    colors: [
                        color.opacity(colorScheme == .dark ? 0.16 : 0.12),
                        color.opacity(colorScheme == .dark ? 0.05 : 0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            // Outer subtle border
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        isHovered ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(colorScheme == .dark ? 0.25 : 0.15)),
                        lineWidth: isHovered ? 1.5 : 0.7
                    )
            )
            // Inner Highlight (Claymorphic Glossy Highlight)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.45), lineWidth: 3)
                    .blur(radius: 1.5)
                    .offset(x: 1.5, y: 1.5)
                    .mask(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
            )
            // Inner Shadow (Claymorphic Depth)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), lineWidth: 4)
                    .blur(radius: 2)
                    .offset(x: -2, y: -2)
                    .mask(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
            )
    }
}

private struct ClaymorphicHeroCard: View {
    let emoji: String
    let value: String
    let label: String
    let detail: String
    let color: Color

    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            // Left: Cute Mascot Emoji
            Text(emoji)
                .font(.system(size: 32))
                .scaleEffect(isHovered ? 1.2 : 1.0)
                .rotationEffect(Angle(degrees: isHovered ? -10 : 0))
                .offset(y: isHovered ? -4 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.5), value: isHovered)
                .frame(width: 44, height: 44)

            // Right: Text Details
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(color.opacity(0.8))
                    .lineLimit(1)

                CountUpText(value: value)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(detail)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .frame(width: 240, height: 86, alignment: .leading)
        .background(
            ClaymorphicCard(color: color, isHovered: isHovered)
        )
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .shadow(color: color.opacity(isHovered ? 0.15 : 0.0), radius: 10, x: 0, y: 5)
        .shadow(color: .black.opacity(isHovered ? 0.06 : 0.02), radius: isHovered ? 6 : 3, x: 0, y: isHovered ? 3 : 1)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}

func formatWatchTimeCompact(minutes: Int) -> String {
    let days = minutes / 1440
    let hours = (minutes % 1440) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    return "\(hours)h \(minutes % 60)m"
}
