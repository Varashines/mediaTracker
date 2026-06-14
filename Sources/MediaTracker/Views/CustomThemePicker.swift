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
                    withAnimation(AppTheme.Animation.springSnappy) {
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
                                    .fill(AppTheme.Colors.surfaceSubtle(for: colorScheme))
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    withAnimation(AppTheme.Animation.easeInOut) {
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
                .stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 0.5)
        }
    }
}

struct LightDarkPicker: View {
    @Binding var themePreference: Int
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var pickerNamespace
    @State private var hoveredTag: Int? = nil

    private let options: [(label: String, icon: String)] = [
        ("Light", "sun.max.fill"),
        ("Dark", "moon.fill")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<options.count, id: \.self) { tag in
                let value = tag + 1
                let isSelected = themePreference == value
                let isHovered = hoveredTag == tag

                Button {
                    withAnimation(AppTheme.Animation.springSnappy) {
                        themePreference = value
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: options[tag].icon)
                            .font(AppTheme.Font.caption)
                        Text(options[tag].label)
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
                                    .matchedGeometryEffect(id: "selected_ld_tab", in: pickerNamespace)
                            } else if isHovered {
                                Capsule()
                                    .fill(AppTheme.Colors.surfaceSubtle(for: colorScheme))
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    withAnimation(AppTheme.Animation.easeInOut) {
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
                .stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 0.5)
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
                    withAnimation(AppTheme.Animation.springSnappy) {
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
                                    .fill(AppTheme.Colors.surfaceSubtle(for: colorScheme))
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    withAnimation(AppTheme.Animation.easeInOut) {
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
                .stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 0.5)
        }
    }
}
