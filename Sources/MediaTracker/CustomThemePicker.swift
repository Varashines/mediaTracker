import SwiftUI

struct ThemePicker: View {
    @Binding var themePreference: Int
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // System toggle
            SettingsRow(title: "Use System Appearance", showDivider: themePreference != 0) {
                Toggle("", isOn: Binding(
                    get: { themePreference == 0 },
                    set: { newValue in
                        if newValue {
                            themePreference = 0
                        } else {
                            themePreference = colorScheme == .dark ? 2 : 1
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    if themePreference == 0 {
                        themePreference = colorScheme == .dark ? 2 : 1
                    } else {
                        themePreference = 0
                    }
                }
            }

            // Light/Dark picker (only shown when System is off)
            if themePreference != 0 {
                HStack(spacing: 0) {
                    Spacer().frame(width: 16)
                    pickerButton(tag: 1, label: "Light", icon: "sun.max.fill")
                    Spacer().frame(width: 8)
                    pickerButton(tag: 2, label: "Dark", icon: "moon.fill")
                    Spacer()
                }
                .padding(.vertical, 10)
            }
        }
    }

    private func pickerButton(tag: Int, label: String, icon: String) -> some View {
        let isSelected = themePreference == tag
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                themePreference = tag
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
