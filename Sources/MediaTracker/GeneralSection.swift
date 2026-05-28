import SwiftUI
import ServiceManagement

struct GeneralSection: View {
    @AppStorage("theme_preference") private var themePreference: Int = 0
    @AppStorage("haptics_enabled") private var hapticsEnabled = true
    @AppStorage("audio_enabled") private var audioEnabled = true
    @AppStorage("prevent_sleep_mode") private var preventSleepMode = false
    @AppStorage("auto_mark_episodes_watched") private var autoMarkEpisodesWatched = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(text: "Appearance", color: .blue)
            SettingsCard(color: .blue) {
                ThemePicker(themePreference: $themePreference)
            }

            SettingsSectionHeader(text: "Tracking", color: .green)
            SettingsCard(color: .green) {
                SettingsToggleRow(
                    title: "Auto-Complete TV Shows",
                    subtitle: "Marking a show completed marks all episodes watched",
                    isOn: $autoMarkEpisodesWatched
                )
            }

            SettingsSectionHeader(text: "System", color: .purple)
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
