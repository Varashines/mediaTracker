import SwiftUI

struct ThemePicker: View {
    @Binding var themePreference: Int
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var themeNamespace
    @State private var hoveredTag: Int? = nil

    private let options: [(label: String, icon: String)] = [
        ("System", "circle.lefthalf.filled"),
        ("Light", "sun.max.fill"),
        ("Dark", "moon.fill")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<options.count, id: \.self) { tag in
                let option = options[tag]
                let isSelected = themePreference == tag
                let isHovered = hoveredTag == tag

                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        themePreference = tag
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.icon)
                            .font(AppTheme.Font.caption)
                        Text(option.label)
                            .font(AppTheme.Font.caption)
                    }
                    .foregroundStyle(isSelected ? AppTheme.Colors.accent : .secondary)
                    .frame(height: 28)
                    .padding(.horizontal, 14)
                    .background {
                        ZStack {
                            if isSelected {
                                Capsule()
                                    .fill(AppTheme.Colors.accent.opacity(colorScheme == .dark ? 0.15 : 0.08))
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
    }
}

struct PalettePicker: View {
    @Binding var customThemePalette: Int
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var paletteNamespace
    @State private var hoveredTag: Int? = nil

    private let options: [(label: String, icon: String)] = [
        ("Standard", "sparkles"),
        ("Earth Tones", "leaf.fill"),
        ("Cool Tones", "snowflake")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<options.count, id: \.self) { tag in
                let option = options[tag]
                let isSelected = customThemePalette == tag
                let isHovered = hoveredTag == tag

                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        customThemePalette = tag
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.icon)
                            .font(AppTheme.Font.caption)
                        Text(option.label)
                            .font(AppTheme.Font.caption)
                    }
                    .foregroundStyle(isSelected ? AppTheme.Colors.accent : .secondary)
                    .frame(height: 28)
                    .padding(.horizontal, 14)
                    .background {
                        ZStack {
                            if isSelected {
                                Capsule()
                                    .fill(AppTheme.Colors.accent.opacity(colorScheme == .dark ? 0.15 : 0.08))
                                    .matchedGeometryEffect(id: "selected_palette_tab", in: paletteNamespace)
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
    }
}
