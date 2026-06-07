import SwiftUI

struct PillBadge: View {
    var icon: String? = nil
    var text: String
    var color: Color
    var style: BadgeStyle = .filled

    enum BadgeStyle {
        case filled
        case outlined
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 7, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 7.5, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(color)
        .background {
            Capsule()
                .fill(style == .filled ? color.opacity(0.15) : Color.clear)
        }
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(color.opacity(style == .outlined ? 0.4 : 0), lineWidth: 0.5)
        }
    }
}
