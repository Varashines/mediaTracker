import SwiftUI

// MARK: - Segment Picker (shared component)

private struct SegmentPicker: View {
    let options: [(label: String, icon: String, id: Int)]
    var selectedID: Int
    var onSelect: (Int) -> Void
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var namespace
    @State private var hoveredTag: Int? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.id) { option in
                let isSelected = selectedID == option.id
                let isHovered = hoveredTag == option.id

                Button {
                    withAnimation(AppTheme.Animation.springSnappy) {
                        onSelect(option.id)
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.mini) {
                        Image(systemName: option.icon)
                            .font(AppTheme.Font.caption)
                        Text(option.label)
                            .font(AppTheme.Font.caption)
                    }
                    .foregroundStyle(isSelected ? AppTheme.Colors.accent : .secondary)
                    .frame(height: 28)
                    .padding(.horizontal, AppTheme.Spacing.smallMedium)
                    .background {
                        ZStack {
                            if isSelected {
                                Capsule()
                                    .fill(AppTheme.Colors.accent.opacity(colorScheme == .dark ? 0.15 : 0.08))
                                    .matchedGeometryEffect(id: "selected", in: namespace)
                            } else if isHovered {
                                Capsule()
                                    .fill(AppTheme.Colors.surfaceSubtle(for: colorScheme))
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(AppTheme.Animation.easeInOut) {
                        hoveredTag = hovering ? option.id : nil
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.micro)
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

// MARK: - Public Pickers

struct LightDarkPicker: View {
    @Binding var themePreference: Int

    var body: some View {
        SegmentPicker(
            options: [
                (label: "Light", icon: "sun.max.fill", id: 1),
                (label: "Dark", icon: "moon.fill", id: 2)
            ],
            selectedID: themePreference,
            onSelect: { themePreference = $0 }
        )
    }
}

struct PalettePicker: View {
    @Binding var customThemePalette: Int

    var body: some View {
        SegmentPicker(
            options: [
                (label: "Standard", icon: "sparkles", id: 0),
                (label: "Earth Tones", icon: "leaf.fill", id: 1),
                (label: "Cool Tones", icon: "snowflake", id: 2)
            ],
            selectedID: customThemePalette,
            onSelect: { customThemePalette = $0 }
        )
    }
}
