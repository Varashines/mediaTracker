import SwiftUI
import SwiftData

/// Season cast card styled identically to the top-cast `CastMemberCard`, with
/// the actor's per-season episode count shown as a badge in the lower corner.
struct SeasonCastMemberCard: View {
    let member: SeasonCastMember
    let themeColor: Color
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            CastMemberCardBody(
                name: member.name,
                characterName: member.characterName,
                profileURL: member.profileURL,
                themeColor: themeColor
            )
            .overlay(alignment: .bottomTrailing) {
                episodeCountBadge
            }
        }
        .buttonStyle(.interactive)
        .accessibilityLabel("\(member.name)\(member.characterName.isEmpty ? "" : ", \(member.characterName)"), \(member.episodeCount) episodes")
    }

    private var episodeCountBadge: some View {
        Text("\(member.episodeCount)")
            .font(AppTheme.Font.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
            .padding(6)
    }
}
