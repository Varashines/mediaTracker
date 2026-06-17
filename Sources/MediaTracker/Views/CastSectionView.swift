import SwiftUI
import SwiftData

struct CastSectionView: View {
    let cast: [SimpleCastMember]
    let themeColor: Color
    var onCastSelected: ((String) -> Void)? = nil
    @State private var showAll = false
    @Environment(\.colorScheme) var colorScheme

    private let initialLimit = 6

    var body: some View {
        let visible = showAll || cast.count <= initialLimit
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(visible ? cast : Array(cast.prefix(initialLimit))) { member in
                    CastMemberCard(member: member, themeColor: themeColor) {
                        onCastSelected?(member.name)
                    }
                }
                if !visible {
                    Button {
                        withAnimation(AppTheme.Animation.springSnappy) {
                            showAll = true
                        }
                    } label: {
                        Text("+\(remainingCount)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(themeColor.highContrastAccent(colorScheme: colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(themeColor.opacity(colorScheme == .dark ? 0.15 : 0.10))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(themeColor.opacity(0.2), lineWidth: 0.5)
                            )
                            .frame(height: 90)
                    }
                    .buttonStyle(.interactive)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var remainingCount: Int {
        max(0, cast.count - initialLimit)
    }
}
