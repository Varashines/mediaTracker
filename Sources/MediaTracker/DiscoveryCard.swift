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
        return baseColor
    }

    var body: some View {
        Button(action: action) {
            let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
            let cornerRadius: CGFloat = style == .logo ? 20 : 32
            
            ZStack {
                // Main Layer
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(themeColor.opacity(colorScheme == .dark ? 0.15 : 0.06))
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color(NSColor.windowBackgroundColor))
                            .shadow(color: accent.opacity(isHovered ? 0.12 : 0), radius: isHovered ? 8 : 0, y: isHovered ? 4 : 0)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(accent.opacity(isHovered ? 0.3 : 0.08), lineWidth: isHovered ? 1.5 : 1)
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
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isHovered)
        .onHover { isHovered = $0 }
    }
    
    @ViewBuilder
    private var logoContent: some View {
        ZStack {
            if let logo = node.logoPath, let urlString = APIClient.tmdbImageURL(path: logo, size: "w300"), let url = URL(string: urlString) {
                CachedImage(url: url, targetSize: CGSize(width: 100, height: 50), alwaysPreserveAlpha: true) {
                    _ in
                } placeholder: {
                    Color.secondary.opacity(0.1)
                }
                .aspectRatio(contentMode: .fit)
                .frame(width: isHovered ? 75 : 100, height: isHovered ? 38 : 50)
                .offset(y: isHovered ? -12 : 0)
            } else {
                Text(node.name)
                    .font(.system(size: 16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .offset(y: isHovered ? -12 : 0)
            }
            
            VStack(spacing: 2) {
                if node.logoPath != nil {
                    Text(node.name)
                        .font(.system(size: 12, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
                Text("\(node.count) TITLES")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .opacity(isHovered ? 1 : 0)
            .offset(y: isHovered ? 22 : 35)
            .scaleEffect(isHovered ? 1.0 : 0.9)
        }
        .padding(15)
    }
    
    @ViewBuilder
    private var textContent: some View {
        ZStack {
            Text(node.name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(themeColor.highContrastAccent(colorScheme: colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .offset(y: isHovered ? -10 : 0)

            Text("\(node.count) ITEMS")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.secondary.opacity(0.8))
                .tracking(0.5)
                .opacity(isHovered ? 1 : 0)
                .offset(y: isHovered ? 12 : 20)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
    }
}
