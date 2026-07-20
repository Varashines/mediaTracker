import SwiftUI

struct HallOfFameView: View {
    let stats: LibraryStats
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            if !stats.topRatedActors.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    SectionHeader(title: "Hall of Fame — Cast", icon: "person.2.fill", iconColor: .orange)

                    GlassCard(color: .orange) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 130), spacing: 16)], spacing: 16) {
                            ForEach(Array(stats.topRatedActors.prefix(8).enumerated()), id: \.element.name) { index, person in
                                PersonCard(person: person, themeColor: .orange, rank: index + 1)
                            }
                        }
                        .padding(AppTheme.Spacing.medium)
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }
            }

            if !stats.topRatedCreators.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    SectionHeader(title: "Hall of Fame — Creators", icon: "pencil.and.outline", iconColor: .green)

                    GlassCard(color: .green) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 130), spacing: 16)], spacing: 16) {
                            ForEach(Array(stats.topRatedCreators.prefix(8).enumerated()), id: \.element.name) { index, person in
                                PersonCard(person: person, themeColor: .green, rank: index + 1)
                            }
                        }
                        .padding(AppTheme.Spacing.medium)
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }
            }
        }
    }
}

private struct PersonCard: View {
    let person: VisualPersonStat
    let themeColor: Color
    let rank: Int
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    private var rankEmoji: String {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return "🌟"
        }
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            ZStack(alignment: .topLeading) {
                profilePhoto

                Text(rankEmoji)
                    .font(.system(size: 16))
                    .offset(x: -6, y: -6)
            }

            // Name wrapping to 2 lines
            Text(person.name)
                .font(AppTheme.Font.bodyBold)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 90, height: 32, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)

            // Stats
            VStack(spacing: 2) {
                Text(String(format: "%.0f%%", person.score * 100))
                    .font(AppTheme.Font.monoCaption)
                    .foregroundStyle(themeColor)
                Text("\(person.count) \(person.count == 1 ? "title" : "titles")")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, AppTheme.Spacing.small)
        .padding(.horizontal, AppTheme.Spacing.small)
        .frame(width: 110)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(isHovered
                    ? themeColor.opacity(colorScheme == .dark ? 0.08 : 0.05)
                    : Color.primary.opacity(colorScheme == .dark ? 0.03 : 0.02)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(isHovered ? themeColor.opacity(0.2) : Color.primary.opacity(0.04), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0), radius: 8, y: isHovered ? 4 : 0)
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.springSnappy) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var profilePhoto: some View {
        if let urlString = person.profileURL, let url = URL(string: urlString) {
            CachedImage(url: url, targetSize: CGSize(width: 70, height: 95), priority: .low, themeColor: themeColor) { _ in
            } placeholder: {
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                    .shimmering()
            }
            .scaledToFill()
            .frame(width: 70, height: 95)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                .fill(AppTheme.Colors.surfaceGhost(for: colorScheme))
                .frame(width: 70, height: 95)
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                        .font(AppTheme.Font.title2)
                }
        }
    }
}
