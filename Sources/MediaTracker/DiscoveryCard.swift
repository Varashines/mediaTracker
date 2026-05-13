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
                    .fill(themeColor.opacity(colorScheme == .dark ? (isHovered ? 0.22 : 0.12) : (isHovered ? 0.08 : 0.05)))
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(isHovered ? 0.1 : 0.06) : Color(NSColor.windowBackgroundColor))
                            .shadow(color: colorScheme == .dark ? accent.opacity(isHovered ? 0.25 : 0) : Color.black.opacity(isHovered ? 0.08 : 0), radius: isHovered ? 12 : 0, y: isHovered ? 6 : 0)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(accent.opacity(colorScheme == .dark ? (isHovered ? 0.45 : 0.15) : (isHovered ? 0.2 : 0.08)), lineWidth: isHovered ? 1.5 : 1)
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
        let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
        ZStack {
            // Normal State: Centered Logo or Name
            Group {
                if let logo = node.logoPath, let urlString = APIClient.tmdbImageURL(path: logo, size: "w300"), let url = URL(string: urlString) {
                    CachedImage(url: url, targetSize: CGSize(width: 100, height: 50), alwaysPreserveAlpha: true) {
                        _ in
                    } placeholder: {
                        Color.secondary.opacity(0.1)
                    }
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 50)
                } else {
                    Text(node.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(accent)
                        .multilineTextAlignment(.center)
                }
            }
            .opacity(isHovered ? 0 : 1)
            .scaleEffect(isHovered ? 0.9 : 1.0)
            
            // Hover State: Horizontal Split Info
            HStack(spacing: 0) {
                Text(node.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(colorScheme == .dark ? .white : accent)
                    .lineLimit(1)
                
                Spacer()
                
                Text("\(node.count)")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 24)
            .opacity(isHovered ? 1 : 0)
            .offset(y: isHovered ? 0 : 10)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isHovered)
    }
    
    @ViewBuilder
    private var textContent: some View {
        let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
        HStack(spacing: 0) {
            if !isHovered { Spacer() }
            
            Text(node.name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(isHovered && colorScheme == .dark ? .white : accent)
                .lineLimit(1)
            
            if isHovered {
                Spacer()
                Text("\(node.count)")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .secondary)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, isHovered ? 24 : 12)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isHovered)
    }
}
