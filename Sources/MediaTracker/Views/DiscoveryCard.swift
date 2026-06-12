import SwiftUI

enum DiscoveryCardStyle {
    case logo, text
}

struct DiscoveryCard: View {
    let node: DiscoveryNode
    let style: DiscoveryCardStyle
    var baseColor: Color = .gray
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme

    private var themeColor: Color {
        if style == .logo {
            if let hex = node.themeColorHex, let color = Color(hex: hex) {
                return color
            }
            return Color(white: 0.3)
        }
        if baseColor == .indigo {
            switch node.name {
            case "Action", "Adventure": return .orange
            case "Comedy": return .yellow
            case "Drama": return .blue
            case "Sci-Fi", "Science Fiction", "Fantasy": return .purple
            case "Horror", "Thriller": return .red
            case "Mystery", "Crime": return .indigo
            case "Documentary": return .gray
            case "Animation": return .pink
            case "Family": return .green
            default: return baseColor
            }
        }
        return baseColor
    }

    var body: some View {
        Button(action: action) {
            let cornerRadius: CGFloat = style == .logo ? AppTheme.Radius.medium : AppTheme.Radius.large

            ZStack {
                if style == .logo {
                    logoCard(cornerRadius: cornerRadius)
                    logoContent
                } else {
                    textCard(cornerRadius: cornerRadius)
                    textContent
                }
            }
            .frame(height: style == .logo ? 90 : 60)
            .compositingGroup()
        }
        .buttonStyle(.plain)
        .glassButtonStyle()
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: isHovered ? themeColor.opacity(0.12) : .clear, radius: isHovered ? 8 : 0, y: isHovered ? 4 : 0)
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.85), value: isHovered)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private func logoCard(cornerRadius: CGFloat) -> some View {
        let baseCardColor = AppTheme.Colors.cardFill(for: colorScheme)
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(baseCardColor)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(themeColor.opacity(isHovered ? 0.16 : 0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isHovered ? themeColor.opacity(0.35) : AppTheme.Colors.strokeDefault(for: colorScheme),
                        lineWidth: isHovered ? 1.0 : 0.8
                    )
            }
    }

    @ViewBuilder
    private func textCard(cornerRadius: CGFloat) -> some View {
        let bg = themeColor.opacity(colorScheme == .dark ? (isHovered ? 0.12 : 0.07) : (isHovered ? 0.12 : 0.07))
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(bg)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        themeColor.opacity(colorScheme == .dark ? (isHovered ? 0.28 : 0.15) : (isHovered ? 0.22 : 0.12)),
                        lineWidth: isHovered ? 1.0 : 0.8
                    )
            }
    }

    @ViewBuilder
    private var logoContent: some View {
        let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
        ZStack(alignment: .topTrailing) {
            ZStack {
                if let logo = node.logoPath, let urlString = APIClient.tmdbImageURL(path: logo, size: "w300"), let url = URL(string: urlString) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: AppTheme.Colors.shadowElevated(for: colorScheme), radius: 2, y: 1)

                        CachedImage(url: url, targetSize: CGSize(width: 75, height: 32)) { _ in } placeholder: {
                            Color.secondary.opacity(0.1)
                        }
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 75, height: 32)
                        .padding(4)
                    }
                    .frame(width: 85, height: 40)
                    .opacity(isHovered ? 0.0 : 1.0)
                    .scaleEffect(isHovered ? 0.95 : 1.0)

                    Text(node.name)
                        .font(AppTheme.Font.bodyBold)
                        .foregroundStyle(accent)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                        .opacity(isHovered ? 1.0 : 0.0)
                } else {
                    Text(node.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isHovered {
                Text("\(node.count)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent.opacity(0.8))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(themeColor.opacity(colorScheme == .dark ? 0.12 : 0.05))
                    .clipShape(Capsule())
                    .padding(6)
            }
        }
    }

    @ViewBuilder
    private var textContent: some View {
        let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
        HStack(spacing: 0) {
            Text(node.name)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
                .truncationMode(.tail)

            if isHovered {
                Spacer(minLength: 4)
                Text("\(node.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: isHovered ? .leading : .center)
        .padding(.horizontal, AppTheme.Spacing.medium)
    }
}
