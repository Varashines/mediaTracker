import SwiftUI
import SwiftData

struct CastSectionViewNew: View {
    let cast: [SimpleCastMember]
    let themeColor: Color
    var onCastSelected: ((String) -> Void)? = nil
    
    @State private var isVisible = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(cast) { member in
                    CastMemberCardNew(member: member, themeColor: themeColor) {
                        onCastSelected?(member.name)
                    }
                    .offset(x: isVisible ? 0 : 20)
                    .opacity(isVisible ? 1 : 0)
                    .scrollTransition(axis: .horizontal) { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.6)
                            .scaleEffect(phase.isIdentity ? 1 : 0.9)
                            .offset(y: phase.isIdentity ? 0 : 5)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 15)
        }
        .onAppear {
            withAnimation(.smooth) {
                isVisible = true
            }
        }
    }
}
