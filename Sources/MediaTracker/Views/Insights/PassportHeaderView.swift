import SwiftUI

struct PassportHeaderView: View {
    let stats: LibraryStats
    var onArchetypeTap: (() -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme

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
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
    }
}
