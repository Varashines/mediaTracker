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

    private var isSystem: Bool { themePreference == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            SettingsSectionHeader(text: "Theme", icon: "paintbrush", color: .blue)

            SettingsCard(color: .blue) {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Follow System")
                                .font(AppTheme.Font.body)
                                .foregroundStyle(.primary)
                            Text("Automatically match macOS appearance")
                                .font(AppTheme.Font.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { themePreference == 0 },
                            set: { isSystem in
                                withAnimation(AppTheme.Animation.springSnappy) {
                                    if isSystem {
                                        themePreference = 0
                                    } else {
                                        themePreference = scheme == .dark ? 1 : 2
                                    }
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider()
                        .overlay(AppTheme.Colors.strokeDefault(for: scheme))
                        .padding(.leading, 14)

                    HStack {
                        Text("Appearance")
                            .font(AppTheme.Font.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        LightDarkPicker(themePreference: $themePreference)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .opacity(isSystem ? 0.4 : 1.0)
                    .allowsHitTesting(!isSystem)
                }
            }

            SettingsSectionHeader(text: "Color Palette", icon: "paintbrush", color: .purple)

            SettingsCard(color: .purple) {
                HStack(spacing: 14) {
                    paletteDot(index: 0, accent: .accentColor, label: "Standard")
                    paletteDot(index: 1, accent: Color(hex: "#9B7B6B") ?? .accentColor, label: "Earth")
                    paletteDot(index: 2, accent: Color(hex: "#6E7BB8") ?? .accentColor, label: "Cool")
                    paletteDot(index: 3, accent: Color(hex: "#059669") ?? .accentColor, label: "Forest")
                    paletteDot(index: 4, accent: Color(hex: "#2563EB") ?? .accentColor, label: "Ocean")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 14)
            }

            SettingsSectionHeader(text: "System", icon: "gearshape", color: .purple)

            SettingsCard(color: .purple) {
                toggleRow("Haptic Feedback", subtitle: "Vibrate on interactions", isOn: $hapticsEnabled, showDivider: true)
                toggleRow("Audio Feedback", subtitle: "Play sounds on actions", isOn: $audioEnabled, showDivider: true)
                toggleRow("Launch at Login", subtitle: "Open automatically when you log in", isOn: $launchAtLogin, showDivider: true)
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
                toggleRow("Prevent Sleep", subtitle: "Keep Mac awake for background sync", isOn: $preventSleepMode, showDivider: true)
                toggleRow("Skip Background Tasks", subtitle: "Disable automatic metadata repair on launch", isOn: $skipStartupTasks, showDivider: false)
            }
        }
    }

    private func toggleRow(_ title: String, subtitle: String, isOn: Binding<Bool>, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTheme.Font.body)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: isOn)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if showDivider {
                Divider()
                    .overlay(AppTheme.Colors.strokeDefault(for: scheme))
                    .padding(.leading, 14)
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
                .frame(width: 24, height: 24)
                .overlay {
                    if isSelected {
                        Circle()
                            .fill(.white)
                            .frame(width: 8, height: 8)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
