import SwiftUI
import SwiftData

/// Season-scoped cast strip. Shows the floor-qualifying cast (min(2, 10% of
/// season episodes)) by default — unlike the series "Top Cast", it is not
/// capped to the first six — with a "+N" pill to reveal the rest (cameos).
struct SeasonCastSection: View {
    let cast: [SeasonCastMember]
    let themeColor: Color
    var onCastSelected: ((String) -> Void)? = nil
    @State private var showAll = false

    private var qualifying: [SeasonCastMember] {
        cast.filter { $0.qualifiesForTaste }
    }
    private var cameos: [SeasonCastMember] {
        cast.filter { !$0.qualifiesForTaste }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: AppTheme.Spacing.medium) {
                ForEach(showAll ? cast : qualifying, id: \.persistentModelID) { member in
                    SeasonCastMemberCard(member: member, themeColor: themeColor) {
                        onCastSelected?(member.name)
                    }
                }
                if !showAll && !cameos.isEmpty {
                    CastRevealPill(hiddenCount: cameos.count, themeColor: themeColor) {
                        showAll = true
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.vertical, AppTheme.Spacing.small)
            .scrollTargetLayout()
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
