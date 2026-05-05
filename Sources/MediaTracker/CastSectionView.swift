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
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 15)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isVisible = true
            }
        }
    }
}
