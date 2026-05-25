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
            return Color(red: 0.3, green: 0.3, blue: 0.3)
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
            let bg: Color = {
                let base = themeColor
                if colorScheme == .dark {
                    guard let nsColor = NSColor(base).usingColorSpace(.sRGB) else {
                        return base.opacity(isHovered ? 0.12 : 0.07)
                    }
                    var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0; var a: CGFloat = 0
                    nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
                    let brightness = (r + g + b) / 3
                    if brightness < 0.25 {
                        return Color.white.opacity(isHovered ? 0.28 : 0.18)
                    }
                    return base.opacity(isHovered ? 0.12 : 0.07)
                }
                return base.opacity(isHovered ? 0.12 : 0.07)
            }()
            let border = themeColor.opacity(colorScheme == .dark ? (isHovered ? 0.28 : 0.15) : (isHovered ? 0.22 : 0.12))

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
            .frame(height: style == .logo ? 90 : 60)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .offset(y: isHovered ? -3 : 0)
        .shadow(color: themeColor.opacity(isHovered ? 0.15 : 0.04), radius: isHovered ? 10 : 2, y: isHovered ? 6 : 1)
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.85), value: isHovered)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var logoContent: some View {
        let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
        ZStack {
            // Logo — fades on hover
            Group {
                if let logo = node.logoPath, let urlString = APIClient.tmdbImageURL(path: logo, size: "w300"), let url = URL(string: urlString) {
                    CachedImage(url: url, targetSize: CGSize(width: 80, height: 40)) { _ in } placeholder: {
                        Color.secondary.opacity(0.1)
                    }
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 40)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "tv.fill")
                            .font(.system(size: 22))
                        Text(node.name)
                            .font(AppTheme.Font.caption)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(accent)
                }
            }
            .opacity(isHovered ? 0 : 1)
            .scaleEffect(isHovered ? 0.8 : 1)

            // Name + count — vertically centered on hover
            HStack(spacing: 0) {
                Text(node.name)
                    .font(AppTheme.Font.bodyBold)
                    .fontWeight(.heavy)
                    .foregroundStyle(accent)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 4)

                Text("\(node.count)")
                    .font(AppTheme.Font.bodyBold)
                    .fontWeight(.heavy)
                    .foregroundStyle(accent)
            }
            .scaleEffect(isHovered ? 1 : 0.9)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, AppTheme.Spacing.large)
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.85), value: isHovered)
    }

    @ViewBuilder
    private var textContent: some View {
        let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
        ZStack {
            Text(node.name)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: isHovered ? .leading : .center)
                .scaleEffect(isHovered ? 0.85 : 1.0, anchor: .leading)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text("\(node.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
                    .scaleEffect(isHovered ? 1.0 : 0.01)
                    .opacity(isHovered ? 1.0 : 0.0)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
    }
}
