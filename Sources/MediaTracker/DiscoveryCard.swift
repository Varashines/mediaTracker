import SwiftUI

enum DiscoveryCardStyle {
    case logo, text
}

struct DiscoveryCard: View {
    let node: DiscoveryNode
    let style: DiscoveryCardStyle
    var baseColor: Color = .accentColor
    let action: () -> Void
    
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme

    private var themeColor: Color {
        if style == .logo {
            if let hex = node.themeColorHex, let color = Color(hex: hex) {
                return color
            }
            return .accentColor
        }
        // Genre Color Coding
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
            let bg = themeColor.opacity(colorScheme == .dark ? (isHovered ? 0.18 : 0.10) : (isHovered ? 0.10 : 0.05))
            let border = themeColor.opacity(colorScheme == .dark ? (isHovered ? 0.35 : 0.20) : (isHovered ? 0.22 : 0.10))

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(bg)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(border, lineWidth: isHovered ? 1.0 : 0.8)
                    }

                if style == .logo {
                    logoContent
                } else {
                    textContent
                }
            }
            .frame(height: style == .logo ? 110 : 65)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: themeColor.opacity(isHovered ? 0.12 : 0.04), radius: isHovered ? 6 : 2, y: isHovered ? 3 : 1)
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.85, blendDuration: 0.1), value: isHovered)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var logoContent: some View {
        let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
        ZStack {
            Group {
                if let logo = node.logoPath, let urlString = APIClient.tmdbImageURL(path: logo, size: "w300"), let url = URL(string: urlString) {
                    CachedImage(url: url, targetSize: CGSize(width: 100, height: 50)) { _ in } placeholder: {
                        Color.secondary.opacity(0.1)
                    }
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 50)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
                } else {
                    Text(node.name)
                        .font(AppTheme.Font.title3)
                        .foregroundStyle(accent)
                        .multilineTextAlignment(.center)
                }
            }
            .scaleEffect(isHovered ? 0.7 : 1.0)
            .offset(y: isHovered ? -22 : 0)

            HStack(spacing: 0) {
                Text(node.name)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(accent)
                    .lineLimit(1)

                Spacer()

                Text("\(node.count)")
                    .font(AppTheme.Font.mono.weight(.bold))
                    .foregroundStyle(accent.opacity(0.9))
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .opacity(isHovered ? 1 : 0)
            .offset(y: isHovered ? 28 : 45)
        }
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.85, blendDuration: 0.1), value: isHovered)
    }

    @ViewBuilder
    private var textContent: some View {
        let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
        HStack(spacing: 0) {
            Text(node.name)
                .font(AppTheme.Font.bodyBold)
                .foregroundStyle(accent)
                .lineLimit(1)

            Spacer()

            Text("\(node.count)")
                .font(AppTheme.Font.mono.weight(.bold))
                .foregroundStyle(accent.opacity(0.9))
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
    }
}
