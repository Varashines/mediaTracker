import SwiftUI

struct HallOfFameView: View {
    let stats: LibraryStats
    @Environment(\.colorScheme) var colorScheme

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 160), spacing: 16)]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            if !stats.topRatedActors.isEmpty {
                SectionHeader(title: "Hall of Fame — Cast", icon: "person.2.fill", iconColor: .orange)
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                personGrid(persons: Array(stats.topRatedActors.prefix(7)), color: .orange)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 60, weight: .ultraLight))
                            .foregroundStyle(.orange.opacity(colorScheme == .dark ? 0.05 : 0.03))
                            .offset(x: 12, y: 6)
                            .allowsHitTesting(false)
                    }
            }

            if !stats.topRatedCreators.isEmpty {
                SectionHeader(title: "Hall of Fame — Creators", icon: "pencil.and.outline", iconColor: .green)
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                personGrid(persons: Array(stats.topRatedCreators.prefix(7)), color: .green)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil.and.outline")
                            .font(.system(size: 60, weight: .ultraLight))
                            .foregroundStyle(.green.opacity(colorScheme == .dark ? 0.05 : 0.03))
                            .offset(x: 12, y: 6)
                            .allowsHitTesting(false)
                    }
            }
        }
    }

    @ViewBuilder
    private func personGrid(persons: [VisualPersonStat], color: Color) -> some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(Array(persons.enumerated()), id: \.element.name) { index, person in
                PersonCard(person: person, themeColor: color, rank: index + 1)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
    }
}

private struct PersonCard: View {
    let person: VisualPersonStat
    let themeColor: Color
    let rank: Int
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    var body: some View {
        ZStack {
            // Default state: photo above centered name
            VStack(spacing: AppTheme.Spacing.small) {
                profilePhoto

                Text(person.name)
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .opacity(isHovered ? 0 : 1)
            .scaleEffect(isHovered ? 0.95 : 1.0)

            // Hover state: centered name with stats below
            VStack(spacing: AppTheme.Spacing.small) {
                Spacer()

                Text(person.name)
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                HStack(spacing: 0) {
                    Text("\(String(format: "%.0f", person.score * 100))%")
                        .font(AppTheme.Font.monoCaption)
                        .foregroundStyle(themeColor)
                    Spacer()
                    Text("\(person.count) \(person.count == 1 ? "title" : "titles")")
                        .font(AppTheme.Font.monoCaption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .opacity(isHovered ? 1 : 0)
            .offset(y: isHovered ? 0 : 12)

            // Rank number behind content
            Text("\(rank)")
                .font(.system(size: 70, weight: .black, design: .rounded))
                .foregroundStyle(themeColor.opacity(isHovered ? 0.22 : 0.10))
                .offset(x: -10, y: -6)
                .allowsHitTesting(false)
        }
        .padding(.vertical, AppTheme.Spacing.small)
        .padding(.horizontal, AppTheme.Spacing.small)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 140)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(isHovered ? themeColor.opacity(colorScheme == .dark ? 0.06 : 0.03) : .clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
        .scaleEffect(isHovered ? 1.02 : 1.0)
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
            CachedImage(url: url, targetSize: CGSize(width: 60, height: 88), priority: .low, themeColor: themeColor) { _ in
            } placeholder: {
                ProgressView().controlSize(.small)
            }
            .scaledToFill()
            .frame(width: 60, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                .fill(AppTheme.Colors.surfaceGhost(for: colorScheme))
                .frame(width: 60, height: 88)
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                        .font(AppTheme.Font.title2)
                }
        }
    }
}
