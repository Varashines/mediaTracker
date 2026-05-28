import SwiftUI
import ServiceManagement

struct GeneralSection: View {
    @AppStorage("theme_preference") private var themePreference: Int = 0
    @AppStorage("dark_theme_style") private var darkThemeStyle = 0
    @AppStorage("haptics_enabled") private var hapticsEnabled = true
    @AppStorage("audio_enabled") private var audioEnabled = true
    @AppStorage("prevent_sleep_mode") private var preventSleepMode = false
    @AppStorage("auto_mark_episodes_watched") private var autoMarkEpisodesWatched = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(text: "Appearance", icon: "paintbrush.fill", color: .blue)
            SettingsCard(color: .blue) {
                ThemePicker(themePreference: $themePreference)
                
                if themePreference == 0 || themePreference == 2 {
                    Divider().opacity(0.06).padding(.leading, 16)
                    SettingsRow(title: "Dark Style", subtitle: "Choose Midnight Gray or Pure Black", showDivider: false) {
                        Picker("", selection: $darkThemeStyle) {
                            Text("Midnight").tag(0)
                            Text("AMOLED").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                }
            }

            SettingsSectionHeader(text: "Tracking", icon: "play.circle.fill", color: .green)
            SettingsCard(color: .green) {
                SettingsToggleRow(
                    title: "Auto-Complete TV Shows",
                    subtitle: "Marking a show completed marks all episodes watched",
                    isOn: $autoMarkEpisodesWatched
                )
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
