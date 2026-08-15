import SwiftUI

struct HallOfFameView: View {
    let stats: LibraryStats

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            if stats.topRatedActors.count > 1 {
                InsightsSectionCard(title: "Hall of Fame", secondLine: "Cast") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: AppTheme.Spacing.large) {
                            ForEach(Array(stats.topRatedActors.prefix(10).enumerated()), id: \.element.name) { index, person in
                                PersonRankCard(
                                    rank: index + 1,
                                    name: person.name,
                                    score: person.score,
                                    profileURL: person.profileURL,
                                    accentColor: .purple,
                                    style: .cast
                                )
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        .padding(.vertical, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
            }

            if stats.topRatedCreators.count > 1 {
                InsightsSectionCard(title: "Directors", secondLine: "Visionaries") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: AppTheme.Spacing.large) {
                            ForEach(Array(stats.topRatedCreators.prefix(10).enumerated()), id: \.element.name) { index, person in
                                PersonRankCard(
                                    rank: index + 1,
                                    name: person.name,
                                    score: person.score,
                                    profileURL: person.profileURL,
                                    accentColor: .indigo,
                                    style: .director
                                )
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        .padding(.vertical, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
            }
        }
    }
}

/// Person rank card: giant outlined rank typography overlapping a Top Cast-style
/// rectangular card (image left + name/score right).
struct PersonRankCard: View {
    enum Style {
        case cast
        case director
    }

    let rank: Int
    let name: String
    let score: Double
    let profileURL: String?
    let accentColor: Color
    let style: Style

    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    private var cardRadius: CGFloat {
        style == .cast ? AppTheme.Radius.medium : AppTheme.Radius.small
    }

    var body: some View {
        HStack(alignment: .center, spacing: -12) {
            // Giant outlined rank number
            ZStack {
                Text("\(rank)")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(
                        colorScheme == .dark
                            ? Color.white.opacity(0.12)
                            : Color.black.opacity(0.08)
                    )

                Text("\(rank)")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(.clear)
                    .overlay(
                        Text("\(rank)")
                            .font(.system(size: 72, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        accentColor,
                                        accentColor.opacity(0.45)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
            .frame(width: rank >= 10 ? 95 : 50, height: 80, alignment: .center)
            .allowsHitTesting(false)

            // Rectangular card: photo left, text right
            HStack(spacing: 0) {
                Group {
                    if let profileURL, let url = URL(string: profileURL) {
                        CachedImage(url: url, targetSize: CGSize(width: 60, height: 90), priority: .low) { _ in
                        } placeholder: {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                                .shimmering()
                        }
                        .scaledToFill()
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [
                                    accentColor.opacity(colorScheme == .dark ? 0.25 : 0.15),
                                    accentColor.opacity(colorScheme == .dark ? 0.08 : 0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: style == .cast ? "person.fill" : "video.fill")
                                .font(AppTheme.Font.title2)
                                .foregroundStyle(accentColor.opacity(0.7))
                        }
                    }
                }
                .frame(width: 60, height: 90)
                .clipped()

                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                    Text(name)
                        .font(AppTheme.Font.bodyBold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(accentColor)
                        Text("\(String(format: "%.0f", score * 100))%")
                            .font(AppTheme.Font.caption2.monospacedDigit())
                            .foregroundStyle(accentColor)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.small)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 175, height: 90)
            .background(ClaymorphicSurface(cornerRadius: cardRadius, isHovered: isHovered))
            .overlay(
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .stroke(
                        style == .cast
                            ? accentColor.opacity(colorScheme == .dark ? 0.35 : 0.25)
                            : accentColor.opacity(colorScheme == .dark ? 0.2 : 0.12),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: .black.opacity(isHovered ? 0.08 : 0), radius: 6, y: 3)
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onHover { isHovered = $0 }
    }
}
