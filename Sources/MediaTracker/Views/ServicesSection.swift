import SwiftUI
import UserNotifications

struct ServicesSection: View {
    @AppStorage("tmdb_api_key") private var tmdbApiKey = ""
    @AppStorage("omdb_api_key") private var omdbApiKey = ""
    @AppStorage(UserDefaultsKeys.mmAPIKey.rawValue) private var mmApiKey = ""
    @AppStorage("notifications_enabled") private var notificationsEnabled = true
    @AppStorage("notifications_movies") private var movieNotificationsEnabled = true
    @AppStorage("notifications_tv") private var tvNotificationsEnabled = true
    @AppStorage("notifications_time") private var notificationTime: Double = 9 * 3600

    @State private var showTMDBKey = false
    @State private var showOMDBKey = false
    @State private var showMMKey = false
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            SettingsSectionHeader(text: "API Keys", icon: "key.fill", color: .green)

            SettingsCard(color: .green) {
                VStack(spacing: 0) {
                    apiKeyRow("TMDB", subtitle: "Movie & TV metadata", binding: $tmdbApiKey, showKey: $showTMDBKey, link: "https://www.themoviedb.org/settings/api", showDivider: true)
                    apiKeyRow("OMDb", subtitle: "Rotten Tomatoes scores", binding: $omdbApiKey, showKey: $showOMDBKey, link: "https://www.omdbapi.com/apikey.aspx", showDivider: true)
                    apiKeyRow("MooreMetrics", subtitle: "Show recommendations", binding: $mmApiKey, showKey: $showMMKey, link: "https://www.mooremetrics.com", showDivider: false)
                }
            }

            SettingsSectionHeader(text: "Notifications", icon: "bell.badge.fill", color: .red)

            SettingsCard(color: .red) {
                VStack(spacing: 0) {
                    SettingsToggleRow(title: "Enable Notifications", subtitle: "Get notified about new episodes and movies", showDivider: notificationsEnabled, isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, enabled in
                            if enabled {
                                Task {
                                    await NotificationManager.shared.requestPermission()
                                    await NotificationManager.shared.scheduleAllUpcomingNotifications()
                                }
                            } else {
                                Task { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }
                            }
                        }

                    if notificationsEnabled {
                        SettingsRow(title: "Channels", subtitle: "Select notification categories", showDivider: true) {
                            HStack(spacing: AppTheme.Spacing.tiny) {
                                channelChip("Movies", isOn: $movieNotificationsEnabled)
                                channelChip("TV Shows", isOn: $tvNotificationsEnabled)
                            }
                        }

                        SettingsLabeledRow(title: "Delivery Time", subtitle: "Daily notification schedule", showDivider: true) {
                            DatePicker("", selection: Binding(
                                get: { Date(timeIntervalSince1970: notificationTime) },
                                set: { notificationTime = $0.timeIntervalSince1970.truncatingRemainder(dividingBy: TimeInterval.secondsInDay) }
                            ), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .controlSize(.small)
                        }

                        SettingsRow(title: "Reschedule", subtitle: "Refresh notification queue", showDivider: false) {
                            SettingsButton(title: "Reschedule All") {
                                Task { await NotificationManager.shared.scheduleAllUpcomingNotifications() }
                            }
                        }
                    }
                }
            }
        }
    }

    private func apiKeyRow(_ name: String, subtitle: String, binding: Binding<String>, showKey: Binding<Bool>, link: String, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                    HStack(spacing: AppTheme.Spacing.mini) {
                        Text(name)
                            .font(AppTheme.Font.settingsRowTitle)
                            .foregroundStyle(.primary)
                        StatusBadge(text: binding.wrappedValue.isEmpty ? "Missing" : "Connected", isActive: !binding.wrappedValue.isEmpty)
                    }
                    Text(subtitle)
                        .font(AppTheme.Font.settingsSubtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Link(destination: URL(string: link)!) {
                    Image(systemName: "arrow.up.right.square")
                        .font(AppTheme.Font.label)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)

            HStack(spacing: AppTheme.Spacing.tiny) {
                ZStack(alignment: .trailing) {
                    if showKey.wrappedValue {
                        TextField("Enter API key...", text: binding)
                    } else {
                        SecureField("Enter API key...", text: binding)
                    }
                }
                .textFieldStyle(.plain)
                .font(AppTheme.Font.label)
                .padding(.vertical, AppTheme.Spacing.mini)
                .padding(.horizontal, AppTheme.Spacing.tiny)
                .background(AppTheme.Colors.surfaceGhost(for: scheme))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                        .stroke(AppTheme.Colors.strokeDefault(for: scheme), lineWidth: 0.5)
                )

                Button {
                    showKey.wrappedValue.toggle()
                } label: {
                    Image(systemName: showKey.wrappedValue ? "eye.slash" : "eye")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showKey.wrappedValue ? "Hide API key" : "Show API key")
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.bottom, AppTheme.Spacing.small)

            if showDivider {
                Rectangle()
                    .fill(AppTheme.Colors.strokeDefault(for: scheme))
                    .frame(height: 1)
                    .padding(.leading, AppTheme.Spacing.medium)
            }
        }
    }

    private func channelChip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(AppTheme.Animation.springSnappy) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.micro) {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(AppTheme.Font.label)
                    .foregroundStyle(isOn.wrappedValue ? AppTheme.Colors.accent : .secondary)
                Text(title)
                    .font(AppTheme.Font.label)
                    .foregroundStyle(isOn.wrappedValue ? .primary : .secondary)
            }
            .padding(.horizontal, AppTheme.Spacing.tiny)
            .padding(.vertical, AppTheme.Spacing.micro)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(isOn.wrappedValue ? AppTheme.Colors.accent.opacity(0.06) : Color.primary.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }
}
