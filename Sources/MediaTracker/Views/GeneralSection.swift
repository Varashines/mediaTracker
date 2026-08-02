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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            // MARK: - Appearance
            SettingsSectionHeader(text: "Appearance", icon: "paintbrush")
            SettingsCard {
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

                    SettingsRow(title: "Appearance Mode", showDivider: true) {
                        LightDarkPicker(themePreference: $themePreference)
                    }
                    .opacity(isSystem ? 0.4 : 1.0)
                    .allowsHitTesting(!isSystem)

                    SettingsLabeledRow(title: "Theme Palette", showDivider: true) {
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
                                            .frame(width: 40, height: 24)

                                        if isSelected {
                                            Circle()
                                                .fill(.white)
                                                .frame(width: 6, height: 6)
                                                .shadow(color: .black.opacity(0.3), radius: 1)
                                        }
                                    }
                                    .contentShape(Capsule())
                                    .help(preset.name)
                                    .accessibilityLabel(preset.name)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    SettingsToggleRow(title: "Use Graphic Logos", subtitle: "Show graphical title logos in headers", showDivider: false, isOn: $useTitleLogos)
                }
            }

            // MARK: - Feedback & Interactivity
            SettingsSectionHeader(text: "Interactivity", icon: "speaker.wave.2")
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsToggleRow(title: "Haptic Feedback", subtitle: "Vibrate on key interactions", showDivider: true, isOn: $hapticsEnabled)
                    SettingsToggleRow(title: "Audio Feedback", subtitle: "Play subtle sound effects on actions", showDivider: false, isOn: $audioEnabled)
                }
            }

            // MARK: - Power & Startup
            SettingsSectionHeader(text: "Power & Startup", icon: "bolt")
            SettingsCard {
                VStack(spacing: 0) {
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
                    
                    SettingsToggleRow(title: "Prevent Sleep", subtitle: "Keep Mac awake during active background sync", showDivider: false, isOn: $preventSleepMode)
                }
            }

            // MARK: - Performance
            SettingsSectionHeader(text: "Performance", icon: "speedometer")
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsToggleRow(title: "Reduce Visual Effects", subtitle: "Disable blurs, gradients, and animations", showDivider: true, isOn: Binding(
                        get: { AppThemeCoordinator.shared.reduceVisualEffects },
                        set: { v in
                            UserDefaults.standard.set(v, forKey: "reduce_visual_effects")
                        }
                    ))

                    SettingsToggleRow(title: "Skip Launch Background Tasks", subtitle: "Disable automatic metadata repair on startup", showDivider: false, isOn: $skipStartupTasks)
                }
            }
        }
    }
}
