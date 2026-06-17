import SwiftUI

struct HallOfFameView: View {
    let stats: LibraryStats

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            if !stats.topRatedActors.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(AppTheme.Font.heading)
                            .foregroundStyle(.orange)
                        Text("Hall of Fame — Cast")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.orange)
                            .kerning(1.2)
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(Array(stats.topRatedActors.prefix(8).enumerated()), id: \.element.name) { index, person in
                                let member = SimpleCastMember(
                                    id: person.name,
                                    name: person.name,
                                    characterName: "\(person.count) titles",
                                    profileURL: person.profileURL,
                                    order: index
                                )
                                CastMemberCard(member: member, themeColor: .orange)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        .padding(.vertical, 4)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }

            if !stats.topRatedCreators.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil.and.outline")
                            .font(AppTheme.Font.heading)
                            .foregroundStyle(.green)
                        Text("Hall of Fame — Creators")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.green)
                            .kerning(1.2)
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(Array(stats.topRatedCreators.prefix(8).enumerated()), id: \.element.name) { index, person in
                                let member = SimpleCastMember(
                                    id: person.name,
                                    name: person.name,
                                    characterName: "\(person.count) titles",
                                    profileURL: person.profileURL,
                                    order: index
                                )
                                CastMemberCard(member: member, themeColor: .green)
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
