import SwiftUI
import SwiftData

struct CastSectionViewNew: View {
    let cast: [SimpleCastMember]
    let themeColor: Color
    var onCastSelected: ((String) -> Void)? = nil
    
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView(.horizontal, showsIndicators: false) {
                let filteredCast = cast.filter { $0.characterName != "Creator" && $0.characterName != "Director" }
                let sortedCast = filteredCast.sorted(by: { $0.order < $1.order })

                LazyHStack(alignment: .center, spacing: 16) {
                    ForEach(Array(sortedCast.enumerated()), id: \.element.id) { index, member in
                        CastMemberCardNew(member: member, themeColor: themeColor) {
                            onCastSelected?(member.name)
                        }
                        .offset(x: isVisible ? 0 : 40)
                        .opacity(isVisible ? 1 : 0)
                        .scaleEffect(isVisible ? 1.0 : 0.95)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.8)
                            .delay(Double(index) * 0.05),
                            value: isVisible
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 15)
            }
        }
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
    }
}
