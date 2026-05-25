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
            let border = style == .logo
                ? (isHovered ? themeColor.opacity(0.35) : Color.primary.opacity(0.06))
                : themeColor.opacity(colorScheme == .dark ? (isHovered ? 0.28 : 0.15) : (isHovered ? 0.22 : 0.12))

            ZStack {
                if style == .logo {
                    let baseCardColor = colorScheme == .dark ? Color(white: 0.14) : Color(white: 0.94)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(baseCardColor)
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(themeColor.opacity(isHovered ? 0.16 : 0.08))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(border, lineWidth: isHovered ? 1.0 : 0.8)
                        }
                    
                    logoContent
                } else {
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
                    
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(bg)
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(border, lineWidth: isHovered ? 1.0 : 0.8)
                        }
                    
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
        ZStack(alignment: .topTrailing) {
            // Centered Logo or Name
            ZStack {
                if let logo = node.logoPath, let urlString = APIClient.tmdbImageURL(path: logo, size: "w300"), let url = URL(string: urlString) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 2, y: 1)
                        
                        CachedImage(url: url, targetSize: CGSize(width: 75, height: 32)) { _ in } placeholder: {
                            Color.secondary.opacity(0.1)
                        }
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 75, height: 32)
                        .padding(4)
                    }
                    .frame(width: 85, height: 40)
                    .opacity(isHovered ? 0.15 : 1.0)
                    .scaleEffect(isHovered ? 0.95 : 1.0)
                    
                    if isHovered {
                        Text(node.name)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 8)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                } else {
                    Text(node.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Count badge in top-right (only on hover)
            if isHovered {
                Text("\(node.count)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent.opacity(0.8))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.05))
                    .clipShape(Capsule())
                    .padding(6)
                    .transition(.opacity.combined(with: .scale))
            }
        }
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
