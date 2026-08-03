import SwiftUI

struct HallOfFameView: View {
    let stats: LibraryStats

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            if stats.topRatedActors.count > 1 {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("Hall of Fame — Cast")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.orange)
                            .kerning(1.2)
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: AppTheme.Spacing.large) {
                            ForEach(Array(stats.topRatedActors.prefix(6).enumerated()), id: \.element.name) { index, person in
                                PersonPillCard(
                                    rank: index + 1,
                                    name: person.name,
                                    score: person.score,
                                    profileURL: person.profileURL,
                                    themeColor: .orange
                                )
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        .padding(.vertical, 4)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }

            if stats.topRatedCreators.count > 1 {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil.and.outline")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.green)
                        Text("Hall of Fame — Creators")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.green)
                            .kerning(1.2)
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: AppTheme.Spacing.large) {
                            ForEach(Array(stats.topRatedCreators.prefix(6).enumerated()), id: \.element.name) { index, person in
                                PersonPillCard(
                                    rank: index + 1,
                                    name: person.name,
                                    score: person.score,
                                    profileURL: person.profileURL,
                                    themeColor: .green
                                )
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        .padding(.vertical, 4)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
    }
}

private struct PersonPillCard: View {
    let rank: Int
    let name: String
    let score: Double
    let profileURL: String?
    let themeColor: Color
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    var body: some View {
        ZStack {
            if let profileURL, let url = URL(string: profileURL) {
                CachedImage(url: url, targetSize: CGSize(width: 70, height: 90), priority: .low, themeColor: themeColor) { _ in
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                }
                .scaledToFill()
                .frame(width: 70, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .opacity(isHovered ? 0 : 1)
                .scaleEffect(isHovered ? 0.95 : 1.0)

                VStack(spacing: 4) {
                    Text(name)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text("\(String(format: "%.0f", score * 100))% taste match")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(themeColor)
                }
                .padding(.horizontal, 4)
                .opacity(isHovered ? 1 : 0)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(themeColor.opacity(0.5))

                    Text(name)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if isHovered {
                        Text("\(String(format: "%.0f", score * 100))% taste match")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(themeColor)
                            .transition(.opacity)
                    }
                }
            }

            Text("\(rank)")
                .font(.system(size: 70, weight: .black, design: .rounded))
                .foregroundStyle(themeColor.opacity(isHovered ? 0.22 : 0.10))
                .offset(x: -10, y: -6)
                .allowsHitTesting(false)
        }
        .frame(width: 160, height: 100)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(isHovered ? themeColor.opacity(colorScheme == .dark ? 0.06 : 0.03) : AppTheme.Colors.cardFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(themeColor.opacity(isHovered ? 0.25 : 0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0), radius: 8, y: isHovered ? 4 : 0)
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onHover { isHovered = $0 }
    }
}
