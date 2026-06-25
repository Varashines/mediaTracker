import SwiftUI

struct PassportHeaderView: View {
    let stats: LibraryStats
    var onArchetypeTap: (() -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme

    private var stamps: [(icon: String, label: String, color: Color)] {
        var result: [(String, String, Color)] = []
        let total = stats.totalMovies + stats.totalTVShows
        if total >= 50 {
            result.append(("film.fill", "\(total) stories", .orange))
        }
        let totalWatched = stats.completedMovies + stats.completedTVShows
        if totalWatched >= 25 {
            result.append(("checkmark.seal.fill", "\(totalWatched) done", .teal))
        }
        if stats.totalWatchTimeMinutes >= 1440 {
            let days = stats.totalWatchTimeMinutes / 1440
            result.append(("clock.fill", "\(days) days", .pink))
        }
        return Array(result.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(alignment: .lastTextBaseline, spacing: AppTheme.Spacing.small) {
                Text("Cinema Passport")
                    .font(AppTheme.Font.title)
                    .foregroundStyle(.primary)

                Spacer()

                ArchetypeBadge(archetype: stats.archetype, onTap: onArchetypeTap)
            }

            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if let memberSince = stats.memberSince {
                    Text("Member since \(memberSince.formatted(.dateTime.year()))")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Your journey starts here")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !stamps.isEmpty {
                HStack(spacing: AppTheme.Spacing.tiny) {
                    ForEach(stamps.indices, id: \.self) { idx in
                        let stamp = stamps[idx]
                        HStack(spacing: 3) {
                            Image(systemName: stamp.icon)
                                .font(.system(size: 7))
                            Text(stamp.label)
                                .font(AppTheme.Font.tiny)
                                .kerning(0.5)
                        }
                        .foregroundStyle(stamp.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(stamp.color.opacity(0.3), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(stamp.color.opacity(0.06))
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
        .padding(.vertical, AppTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .fill(AppTheme.Colors.accent.opacity(colorScheme == .dark ? 0.06 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(AppTheme.Colors.accent.opacity(0.15), lineWidth: 0.5)
        )
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "popcorn.fill")
                .font(.system(size: 80, weight: .ultraLight))
                .foregroundStyle(AppTheme.Colors.accent.opacity(0.05))
                .offset(x: 20, y: 10)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(AppTheme.Colors.accent.opacity(0.04))
                .offset(x: -8, y: -8)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
    }
}
