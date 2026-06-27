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

                    SettingsLabeledRow(title: "Appearance", showDivider: true) {
                        LightDarkPicker(themePreference: $themePreference)
                    }
                    .opacity(isSystem ? 0.4 : 1.0)
                    .allowsHitTesting(!isSystem)

                    SettingsToggleRow(title: "Use Graphic Logos", subtitle: "Show graphical title logos in detailed view headers when available", showDivider: false, isOn: $useTitleLogos)
                }
            }

            SettingsSectionHeader(text: "Color Palette", icon: "paintbrush", color: .purple)

            SettingsCard(color: .purple) {
                VStack(spacing: 0) {
                    HStack(spacing: AppTheme.Spacing.smallMedium) {
                        paletteDot(index: 0, accent: Color.accentColor, label: "Standard")
                        paletteDot(index: 1, accent: Color(hex: "#C47A5A") ?? .accentColor, label: "Earth")
                        paletteDot(index: 2, accent: Color(hex: "#7B8CDE") ?? .accentColor, label: "Cool")
                        paletteDot(index: 3, accent: Color(hex: "#10B981") ?? .accentColor, label: "Forest")
                        paletteDot(index: 4, accent: Color(hex: "#3B82F6") ?? .accentColor, label: "Ocean")
                        paletteDot(index: 5, accent: Color(hex: "#D97706") ?? .accentColor, label: "Dusk")
                        paletteDot(index: 6, accent: Color(hex: "#8B5CF6") ?? .accentColor, label: "Midnight")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.smallMedium)
                    .padding(.horizontal, AppTheme.Spacing.smallMedium)
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
                    SettingsToggleRow(title: "Skip Background Tasks", subtitle: "Disable automatic metadata repair on launch", showDivider: false, isOn: $skipStartupTasks)
                }
            }
        }
    }

    private func paletteDot(index: Int, accent: Color, label: String) -> some View {
        let isSelected = customThemePalette == index
        return Button {
            withAnimation(AppTheme.Animation.springSnappy) {
                customThemePalette = index
            }
        } label: {
            Circle()
                .fill(accent)
                .frame(width: AppTheme.Spacing.large, height: AppTheme.Spacing.large)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(accent.isLightColor ? .black : .white)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
