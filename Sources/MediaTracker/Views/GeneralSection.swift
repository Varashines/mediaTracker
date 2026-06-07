import SwiftUI
import ServiceManagement

struct GeneralSection: View {
    @AppStorage("theme_preference") private var themePreference: Int = 0
    @AppStorage("custom_theme_palette") private var customThemePalette = 0
    @AppStorage("haptics_enabled") private var hapticsEnabled = true
    @AppStorage("audio_enabled") private var audioEnabled = true
    @AppStorage("prevent_sleep_mode") private var preventSleepMode = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(text: "Appearance", icon: "paintbrush.fill", color: .blue)
            SettingsCard(color: .blue) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Theme Mode")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("Follow system or force light/dark appearance")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        
                        ThemePicker(themePreference: $themePreference)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    
                    Divider().opacity(0.06).padding(.horizontal, 16)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Theme Palette")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("Choose custom background and accent variations")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        
                        PalettePicker(customThemePalette: $customThemePalette)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
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
}
