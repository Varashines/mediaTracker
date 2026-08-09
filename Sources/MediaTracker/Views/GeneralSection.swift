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
    @Namespace private var paletteNamespace
    @State private var isHoveredPreset: Int? = nil
    @State private var showResetConfirmation = false

    private var isSystem: Bool { themePreference == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            // MARK: - Appearance
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsToggleRow(title: "Follow System", subtitle: nil, showDivider: true, isOn: Binding(
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

                    SettingsRow(
                        title: "Theme Palette",
                        subtitle: AppThemeCoordinator.presets[safe: themePreset]?.name ?? "Mac",
                        showDivider: true
                    ) {
                        HStack(spacing: AppTheme.Spacing.smallMedium) {
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
                                        Circle()
                                            .fill(color)
                                            .frame(width: 22, height: 22)
                                            .overlay {
                                                Circle()
                                                    .stroke(isSelected ? color.readableForeground : Color.primary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                                                    .padding(-3)
                                            }
                                            .if(isSelected) {
                                                $0.matchedGeometryEffect(id: "palettePill", in: paletteNamespace)
                                            }
                                    }
                                    .contentShape(Circle())
                                    .help(preset.name)
                                    .accessibilityLabel(preset.name)
                                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                                }
                                .buttonStyle(.plain)
                                .scaleEffect(isHoveredPreset == index ? 1.15 : 1.0)
                                .animation(AppTheme.Animation.springSnappy, value: isSelected)
                                .animation(AppTheme.Animation.springSnappy, value: isHoveredPreset)
                                .onHover { hovering in
                                    withAnimation(AppTheme.Animation.microInteraction) {
                                        isHoveredPreset = hovering ? index : nil
                                    }
                                }
                            }
                        }
                    }

                    SettingsToggleRow(title: "Use Graphic Logos", subtitle: "Show graphical title logos in headers", showDivider: false, isOn: $useTitleLogos)
                }
            }

            // MARK: - Feedback & Interactivity
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsToggleRow(title: "Haptic Feedback", subtitle: nil, showDivider: true, isOn: $hapticsEnabled)
                    SettingsToggleRow(title: "Audio Feedback", subtitle: nil, showDivider: false, isOn: $audioEnabled)
                }
            }

            // MARK: - Power & Startup
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsToggleRow(title: "Launch at Login", subtitle: nil, showDivider: true, isOn: $launchAtLogin)
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
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsToggleRow(title: "Reduce Visual Effects", subtitle: "Disable blurs, gradients, and animations", showDivider: true, isOn: Binding(
                        get: { AppThemeCoordinator.shared.reduceVisualEffects },
                        set: { v in
                            UserDefaults.standard.set(v, forKey: "reduce_visual_effects")
                        }
                    ))

                    SettingsToggleRow(title: "Skip Launch Background Tasks", subtitle: "Disable automatic metadata repair on startup", showDivider: true, isOn: $skipStartupTasks)

                    SettingsRow(title: "Reset Settings to Defaults", subtitle: "Restore all preferences to their default values", showDivider: false) {
                        SettingsButton(title: "Reset", color: .orange) {
                            showResetConfirmation = true
                        }
                    }
                }
            }
        }
        .confirmationDialog("Reset Settings to Defaults?", isPresented: $showResetConfirmation) {
            Button("Reset All Settings", role: .destructive) {
                resetSettingsToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your library data will not be affected. Appearance, notifications, and other preferences will be restored to defaults.")
        }
    }

    private func resetSettingsToDefaults() {
        let defaults = UserDefaults.standard

        let keys: [UserDefaultsKeys] = [
            .themePreference, .themePreset, .backgroundIntensity, .useTitleLogos,
            .reduceVisualEffects, .hapticsEnabled, .audioEnabled, .preventSleepMode,
            .skipStartupTasks, .notificationsEnabled, .notificationsMovies,
            .notificationsTV, .notificationsTime, .discoveryAutoSync, .recentSearches
        ]
        for key in keys {
            defaults.removeObject(forKey: key.rawValue)
        }
        // Fallback keys written via @AppStorage raw strings
        defaults.removeObject(forKey: "notifications_time")

        defaults.removeObject(forKey: "mm_api_key")
        defaults.removeObject(forKey: "mm_debug_mode")

        if launchAtLogin {
            try? SMAppService.mainApp.unregister()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }

        AppErrorState.shared.showToast("Settings reset to defaults", style: .success)
    }
}
