import SwiftUI

struct TalentLedgerView: View {
    let stats: LibraryStats

    var body: some View {
        VStack(spacing: AppTheme.Spacing.section) {
            // Actors Column / Row
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text("TOP RATED CAST")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                if stats.topRatedActors.isEmpty {
                    DashboardCard {
                        HStack {
                            Spacer()
                            Text("No actor data")
                                .font(AppTheme.Font.body)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(height: 80)
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(stats.topRatedActors.prefix(10).enumerated()), id: \.element.name) { index, person in
                                TalentCardView(person: person, rank: index + 1, color: .orange)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        .padding(.vertical, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }

            // Creators Column / Row
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text("TOP RATED CREATORS")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                if stats.topRatedCreators.isEmpty {
                    DashboardCard {
                        HStack {
                            Spacer()
                            Text("No creator data")
                                .font(AppTheme.Font.body)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(height: 80)
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(stats.topRatedCreators.prefix(10).enumerated()), id: \.element.name) { index, person in
                                TalentCardView(person: person, rank: index + 1, color: .green)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        .padding(.vertical, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
    }
}

struct TalentCardView: View {
    let person: VisualPersonStat
    let rank: Int
    let color: Color

    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Left: Profile Image (full height)
            Group {
                if let urlString = person.profileURL, let url = URL(string: urlString) {
                    CachedImage(url: url, targetSize: CGSize(width: 44, height: 64), priority: .low, themeColor: color) {
                        ProgressView().controlSize(.small)
                    }
                    .scaledToFill()
                    .frame(width: 44, height: 64)
                } else {
                    ZStack {
                        Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.03)
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 16))
                    }
                    .frame(width: 44, height: 64)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Right: Details
            VStack(alignment: .leading, spacing: 2) {
                ZStack(alignment: .leading) {
                    // Rank shown by default: e.g. "01"
                    Text(String(format: "%02d", rank))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(color.gradient)
                        .opacity(isHovered ? 0.0 : 1.0)
                        .scaleEffect(isHovered ? 0.8 : 1.0)

                    // Percentage shown on hover: e.g. "85%"
                    Text(String(format: "%.0f%%", person.score * 100))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                        .opacity(isHovered ? 1.0 : 0.0)
                        .scaleEffect(isHovered ? 1.0 : 1.2)
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
                .frame(height: 14)

                Text(person.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.trailing, 8)

            Spacer(minLength: 0)
        }
        .frame(width: 180, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isHovered
                        ? AnyShapeStyle(color.gradient)
                        : AnyShapeStyle(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04)),
                    lineWidth: isHovered ? 1.5 : 0.7
                )
        )
        .shadow(color: color.opacity(isHovered ? 0.12 : 0.0), radius: 6, x: 0, y: 3)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}
