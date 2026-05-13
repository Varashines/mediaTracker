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
                            .shadow(color: Color.black.opacity(isHovered ? 0.15 : 0), radius: isHovered ? 10 : 0, y: isHovered ? 5 : 0)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(accent.opacity(colorScheme == .dark ? (isHovered ? 0.4 : 0.12) : (isHovered ? 0.2 : 0.08)), lineWidth: isHovered ? 1.5 : 1)
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
            // 1. Logo or Name (Always Visible, Moves Up on Hover)
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
            .scaleEffect(isHovered ? 0.7 : 1.0)
            .offset(y: isHovered ? -22 : 0)
            
            // 2. Info Split (Appears below logo on hover)
            HStack(spacing: 0) {
                Text(node.name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                
                Spacer()
                
                Text("\(node.count)")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(accent.opacity(0.9))
            }
            .padding(.horizontal, 24)
            .opacity(isHovered ? 1 : 0)
            .offset(y: isHovered ? 28 : 45)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isHovered)
    }
    
    @ViewBuilder
    private var textContent: some View {
        let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
        HStack(spacing: 0) {
            if !isHovered { Spacer() }
            
            Text(node.name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
            
            if isHovered {
                Spacer()
                Text("\(node.count)")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(accent.opacity(0.9))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, isHovered ? 24 : 12)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isHovered)
    }
}
