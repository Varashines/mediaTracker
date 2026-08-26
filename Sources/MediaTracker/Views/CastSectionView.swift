import SwiftUI
import SwiftData

/// Shared "+N" reveal pill used by the cast strips. Shows the hidden count and
/// expands the strip when tapped.
struct CastRevealPill: View {
    let hiddenCount: Int
    let themeColor: Color
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button {
            withAnimation(AppTheme.Animation.springSnappy) {
                action()
            }
        } label: {
            Text("+\(hiddenCount)")
                .font(AppTheme.Font.bodyBold)
                .foregroundStyle(themeColor.highContrastAccent(colorScheme: colorScheme))
                .padding(.horizontal, AppTheme.Spacing.small)
                .padding(.vertical, AppTheme.Spacing.mini)
                .background(
                    Capsule()
                        .fill(themeColor.opacity(colorScheme == .dark ? 0.15 : 0.10))
                )
                .overlay(
                    Capsule()
                        .stroke(themeColor.opacity(0.2), lineWidth: 0.5)
                )
                .frame(height: 90)
                .scaleEffect(isHovered ? 1.04 : 1.0)
                .animation(AppTheme.Animation.springSnappy, value: isHovered)
        }
        .buttonStyle(.interactive)
        .onHover { isHovered = $0 }
        .contentShape(Capsule())
    }
}

struct CastSectionView: View {
    let cast: [SimpleCastMember]
    let themeColor: Color
    var onCastSelected: ((String) -> Void)? = nil
    @State private var showAll = false

    private let initialLimit = 6

    var body: some View {
        let visible = showAll || cast.count <= initialLimit
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: AppTheme.Spacing.medium) {
                ForEach(visible ? cast : Array(cast.prefix(initialLimit))) { member in
                    CastMemberCard(member: member, themeColor: themeColor) {
                        onCastSelected?(member.name)
                    }
                }
                if !visible {
                    CastRevealPill(hiddenCount: remainingCount, themeColor: themeColor) {
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

    private var remainingCount: Int {
        max(0, cast.count - initialLimit)
    }
}
