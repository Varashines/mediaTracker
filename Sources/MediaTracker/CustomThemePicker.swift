import SwiftUI

struct ThemePicker: View {
    @Binding var themePreference: Int
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var themeNamespace
    @State private var hoveredTag: Int? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { tag in
                let label = tag == 0 ? "System" : (tag == 1 ? "Light" : "Dark")
                let icon = tag == 0 ? "circle.lefthalf.filled" : (tag == 1 ? "sun.max.fill" : "moon.fill")
                let isSelected = themePreference == tag
                let isHovered = hoveredTag == tag
                
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        themePreference = tag
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(label)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(height: 28)
                    .padding(.horizontal, 14)
                    .background {
                        ZStack {
                            if isSelected {
                                Capsule()
                                    .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.15 : 0.08))
                                    .matchedGeometryEffect(id: "selected_theme_tab", in: themeNamespace)
                            } else if isHovered {
                                Capsule()
                                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.03))
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        hoveredTag = isHovered ? tag : nil
                    }
                }
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04), lineWidth: 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
