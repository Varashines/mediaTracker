import SwiftUI
import ServiceManagement

struct GeneralSection: View {
    @Environment(\.colorScheme) var scheme
    @AppStorage("theme_preference") private var themePreference: Int = 0
    @AppStorage("custom_theme_palette") private var customThemePalette = 0
    @AppStorage("haptics_enabled") private var hapticsEnabled = true
    @AppStorage("audio_enabled") private var audioEnabled = true
    @AppStorage("prevent_sleep_mode") private var preventSleepMode = false
    @AppStorage("skip_startup_background_tasks") private var skipStartupTasks = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(text: "Appearance", icon: "paintbrush.fill", color: .blue)
            SettingsCard(color: .blue) {
                VStack(alignment: .leading, spacing: 0) {
                    // Unified Light/Dark/System picker
                    SettingsRow(title: "Theme", subtitle: "Choose light, dark, or system appearance", showDivider: true) {
                        ThemePicker(themePreference: $themePreference)
                    }

                    // Color Palette — always visible
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
                SettingsToggleRow(title: "Prevent Sleep", subtitle: "Keep Mac awake for background sync", showDivider: true, isOn: $preventSleepMode)
                SettingsToggleRow(title: "Skip Background Tasks", subtitle: "Disable automatic metadata repair on launch", showDivider: false, isOn: $skipStartupTasks)
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
                        .stroke(Color.white.opacity(0.6), lineWidth: 2.5)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .stroke(AppTheme.Colors.strokeDefault(for: scheme), lineWidth: 0.5)
                }
            }
            .frame(width: 28, height: 28)
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
