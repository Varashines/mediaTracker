import SwiftUI
import ServiceManagement

struct GeneralSection: View {
    @Environment(\.colorScheme) var scheme
    @AppStorage("theme_preference") private var themePreference: Int = 0
    @AppStorage("theme_preset") private var themePreset = 0
    @AppStorage("haptics_enabled") private var hapticsEnabled = true
    @AppStorage("audio_enabled") private var audioEnabled = true
    @AppStorage("prevent_sleep_mode") private var preventSleepMode = false
    @AppStorage("skip_startup_background_tasks") private var skipStartupTasks = false
    @AppStorage("use_title_logos") private var useTitleLogos = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var isSystem: Bool { themePreference == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            SettingsSectionHeader(text: "Theme", icon: "paintbrush", color: .blue)

            SettingsCard(color: .blue) {
                VStack(spacing: 0) {
                    SettingsToggleRow(title: "Follow System", subtitle: "Automatically match macOS appearance", showDivider: true, isOn: Binding(
                        get: { themePreference == 0 },
                        set: { isSystem in
                            withAnimation(AppTheme.Animation.springSnappy) {
                                if isSystem { themePreference = 0 }
                                else { themePreference = scheme == .dark ? 1 : 2 }
                            }
                        }
                    ))

                    SettingsRow(title: "Appearance", showDivider: true) {
                        LightDarkPicker(themePreference: $themePreference)
                    }
                    .opacity(isSystem ? 0.4 : 1.0)
                    .allowsHitTesting(!isSystem)

                    SettingsRow(title: "Palette", showDivider: true) {
                        HStack(spacing: AppTheme.Spacing.medium) {
                            ForEach(0..<AppThemeCoordinator.presets.count, id: \.self) { index in
                                let preset = AppThemeCoordinator.presets[index]
                                let isSelected = themePreset == index
                                let color = Color(hex: preset.accent) ?? .gray

                                Button {
                                    withAnimation(AppTheme.Animation.springSnappy) {
                                        themePreset = index
                                    }
                                } label: {
                                    ZStack {
                                        Capsule()
                                            .fill(color)
                                            .frame(width: 44, height: 26)

                                        if isSelected {
                                            Circle()
                                                .fill(.white)
                                                .frame(width: 6, height: 6)
                                                .shadow(color: .black.opacity(0.3), radius: 1)
                                        }
                                    }
                                    .frame(width: 44, height: 26)
                                    .contentShape(Capsule())
                                    .help(preset.name)
                                    .accessibilityLabel(preset.name)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    SettingsToggleRow(title: "Use Graphic Logos", subtitle: "Show graphical title logos in detailed view headers when available", showDivider: false, isOn: $useTitleLogos)
                }
            }

            SettingsSectionHeader(text: "System", icon: "gearshape", color: .purple)

            SettingsCard(color: .purple) {
                VStack(spacing: 0) {
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
                    SettingsToggleRow(title: "Skip Background Tasks", subtitle: "Disable automatic metadata repair on launch", showDivider: true, isOn: $skipStartupTasks)
                    
                    SettingsToggleRow(title: "Reduce Visual Effects", subtitle: "Disable animations, gradients, blur, and shadows to improve performance", showDivider: false, isOn: Binding(
                        get: { AppThemeCoordinator.shared.reduceVisualEffects },
                        set: { v in
                            UserDefaults.standard.set(v, forKey: "reduce_visual_effects")
                        }
                    ))
                }
            }
        }
    }
}
