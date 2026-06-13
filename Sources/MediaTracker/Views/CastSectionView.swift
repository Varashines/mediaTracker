import SwiftUI
import SwiftData

struct CastSectionView: View {
    let cast: [SimpleCastMember]
    let themeColor: Color
    var onCastSelected: ((String) -> Void)? = nil

    var body: some View {
        AnimatedCarousel(items: cast) { member in
            CastMemberCard(member: member, themeColor: themeColor) {
                onCastSelected?(member.name)
            }
        }
    }
}
