import SwiftUI
import ServiceManagement

struct GeneralSection: View {
    @Environment(\.colorScheme) var scheme
    @AppStorage("theme_preference") private var themePreference: Int = 0
    @AppStorage("custom_theme_palette") private var customThemePalette = 0
    @AppStorage("haptics_enabled") private var hapticsEnabled = true
    @AppStorage("audio_enabled") private var audioEnabled = true
    @AppStorage("prevent_sleep_mode") private var preventSleepMode = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var followSystem: Bool {
        themePreference == 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(text: "Appearance", icon: "paintbrush.fill", color: .blue)
            SettingsCard(color: .blue) {
                VStack(alignment: .leading, spacing: 0) {
                    // Follow System toggle
                    SettingsRow(title: "Follow System", subtitle: "Automatically match macOS appearance", showDivider: !followSystem) {
                        Toggle("", isOn: Binding(
                            get: { followSystem },
                            set: { isOn in
                                if isOn {
                                    themePreference = 0
                                } else {
                                    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                                    themePreference = isDark ? 1 : 2
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                    }

                    if !followSystem {
                        // Light/Dark picker
                        SettingsRow(title: "Appearance", subtitle: nil, showDivider: true) {
                            LightDarkPicker(themePreference: $themePreference)
                        }
                    }

                    // Color Palette — always visible, independent of system/manual mode
                    SettingsRow(title: "Color Palette", subtitle: "Choose accent and background style", showDivider: false) {
                        HStack(spacing: 16) {
                            paletteCircle(index: 0, accent: .accentColor)
                            paletteCircle(index: 1, accent: Color(hex: "#9B7B6B") ?? .accentColor)
                            paletteCircle(index: 2, accent: Color(hex: "#6E7BB8") ?? .accentColor)
                        }
                    }
                }
            }

            SettingsSectionHeader(text: "System", icon: "gearshape.fill", color: .purple)
            SettingsCard(color: .purple) {
                SettingsToggleRow(title: "Haptic Feedback", subtitle: "Vibrate on interactions", showDivider: true, isOn: $hapticsEnabled)
                SettingsToggleRow(title: "Audio Feedback", subtitle: "Play sounds on actions", showDivider: true, isOn: $audioEnabled)
                SettingsToggleRow(title: "Launch at Login", subtitle: "Open automatically when you log in", showDivider: true, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
                            } else {
                                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                            }
                        } catch {
                            AppLogger.error("Failed to update launch at login: \(error)")
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                SettingsToggleRow(title: "Prevent Sleep", subtitle: "Keep Mac awake for background sync", showDivider: false, isOn: $preventSleepMode)
            }
        }
    }

    private func paletteCircle(index: Int, accent: Color) -> some View {
        let isSelected = customThemePalette == index
        return Button {
            withAnimation(AppTheme.Animation.springSnappy) {
                customThemePalette = index
            }
        } label: {
            ZStack {
                Circle()
                    .fill(accent)
                if isSelected {
                    Circle()
                        .stroke(accent.opacity(0.7), lineWidth: 2.5)
                } else {
                    Circle()
                        .stroke(AppTheme.Colors.strokeDefault(for: scheme), lineWidth: 0.5)
                }
            }
            .frame(width: 28, height: 28)
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}
