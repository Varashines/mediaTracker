import SwiftUI

struct TalentLedgerView: View {
    let stats: LibraryStats

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.large) {
            // Actors Column
            VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
                Text("TOP RATED CAST")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                    .padding(.leading, AppTheme.Spacing.micro)

                if stats.topRatedActors.isEmpty {
                    DashboardCard {
                        HStack {
                            Spacer()
                            Text("No actor data")
                                .font(AppTheme.Font.body)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(height: 120)
                    }
                } else {
                    DashboardCard {
                        VStack(spacing: 0) {
                            ForEach(Array(stats.topRatedActors.prefix(5).enumerated()), id: \.element.name) { index, person in
                                TalentRowItem(person: person, rank: index + 1, color: .orange)
                                if index < min(stats.topRatedActors.count, 5) - 1 {
                                    Divider()
                                        .padding(.leading, 64)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Creators Column
            VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
                Text("TOP RATED CREATORS")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                    .padding(.leading, AppTheme.Spacing.micro)

                if stats.topRatedCreators.isEmpty {
                    DashboardCard {
                        HStack {
                            Spacer()
                            Text("No creator data")
                                .font(AppTheme.Font.body)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(height: 120)
                    }
                } else {
                    DashboardCard {
                        VStack(spacing: 0) {
                            ForEach(Array(stats.topRatedCreators.prefix(5).enumerated()), id: \.element.name) { index, person in
                                TalentRowItem(person: person, rank: index + 1, color: .green)
                                if index < min(stats.topRatedCreators.count, 5) - 1 {
                                    Divider()
                                        .padding(.leading, 64)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct TalentRowItem: View {
    let person: VisualPersonStat
    let rank: Int
    let color: Color

    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            // Rank Number
            Text("\(rank)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color.opacity(0.8))
                .frame(width: 20, alignment: .leading)

            // Profile Picture
            Group {
                if let urlString = person.profileURL, let url = URL(string: urlString) {
                    CachedImage(url: url, targetSize: CGSize(width: 32, height: 48), priority: .low, themeColor: color) {
                        ProgressView().controlSize(.small)
                    }
                    .scaledToFill()
                } else {
                    ZStack {
                        Color.primary.opacity(0.04)
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
                    }
                }
            }
            .frame(width: 32, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))

            // Name and Stats
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(person.count) \(person.count == 1 ? "title" : "titles")")
                    .font(AppTheme.Font.small)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Affinity score
            Text(String(format: "%.0f%%", person.score * 100))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.vertical, AppTheme.Spacing.tiny)
    }
}
