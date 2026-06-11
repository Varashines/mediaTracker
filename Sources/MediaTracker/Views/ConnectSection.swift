import SwiftUI
import UserNotifications

struct ConnectSection: View {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(text: "API Keys", icon: "key.fill", color: .green)
            SettingsCard(color: .green) {
                apiRow(
                    name: "TMDB",
                    subtitle: "Movie & TV metadata",
                    apiKey: $tmdbApiKey,
                    showKey: $showTMDBKey,
                    isConnected: !tmdbApiKey.isEmpty,
                    link: URL(string: "https://www.themoviedb.org/settings/api")!
                )
                apiRow(
                    name: "OMDb",
                    subtitle: "Rotten Tomatoes scores",
                    apiKey: $omdbApiKey,
                    showKey: $showOMDBKey,
                    isConnected: !omdbApiKey.isEmpty,
                    link: URL(string: "https://www.omdbapi.com/apikey.aspx")!,
                    showDivider: true
                )
                apiRow(
                    name: "MooreMetrics",
                    subtitle: "Show recommendations",
                    apiKey: $mmApiKey,
                    showKey: $showMMKey,
                    isConnected: !mmApiKey.isEmpty,
                    link: URL(string: "https://www.mooremetrics.com")!,
                    showDivider: false
                )
            }

            SettingsSectionHeader(text: "Notifications", icon: "bell.badge.fill", color: .red)
            SettingsCard(color: .red) {
                SettingsToggleRow(title: "Enable Notifications", subtitle: "Get notified about new episodes and movies", showDivider: false, isOn: $notificationsEnabled)
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Channels")
                            .font(AppTheme.Font.settingsSubtitle)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            channelButton(title: "Movies", icon: "film", isOn: $movieNotificationsEnabled)
                            channelButton(title: "TV Shows", icon: "tv", isOn: $tvNotificationsEnabled)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if notificationsEnabled {
                    SettingsRow(title: "Delivery Time", subtitle: "Daily notification schedule", showDivider: true) {
                        DatePicker("", selection: Binding(
                            get: { Date(timeIntervalSince1970: notificationTime) },
                            set: { notificationTime = $0.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400) }
                        ), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }

                if notificationsEnabled {
                    SettingsRow(title: "Reschedule", subtitle: "Refresh notification queue", showDivider: false) {
                        SettingsButton(title: "Reschedule All") {
                            Task { await NotificationManager.shared.scheduleAllUpcomingNotifications() }
                        }
                    }
                }
            }
    }
}

    private func apiRow(
        name: String,
        subtitle: String,
        apiKey: Binding<String>,
        showKey: Binding<Bool>,
        isConnected: Bool,
        link: URL,
        showDivider: Bool = true
    ) -> some View {
        VStack(spacing: 0) {
            SettingsRow(title: name, subtitle: subtitle, showDivider: false) {
                HStack(spacing: 8) {
                    StatusBadge(text: isConnected ? "Connected" : "Missing", isActive: isConnected)
                }
            }

            HStack(spacing: 8) {
                ZStack(alignment: .trailing) {
                    if showKey.wrappedValue {
                        TextField("Enter API key...", text: apiKey)
                    } else {
                        SecureField("Enter API key...", text: apiKey)
                    }
                }
                .textFieldStyle(.plain)
                .padding(.vertical, 5)
                .padding(.leading, 10)
                .padding(.trailing, 30)
                .background(Color.primary.opacity(0.02))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
                .font(AppTheme.Font.body)
                .overlay(alignment: .trailing) {
                    Button {
                        showKey.wrappedValue.toggle()
                    } label: {
                        Image(systemName: showKey.wrappedValue ? "eye.slash" : "eye")
                            .font(AppTheme.Font.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                    }
                    .buttonStyle(.plain)
                }

                Link(destination: link) {
                    Image(systemName: "arrow.up.right.square")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Get \(name) API key")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if showDivider {
                Rectangle()
                    .fill(AppTheme.Colors.strokeDefault(for: scheme))
                    .frame(height: 1)
                    .padding(.leading, 16)
            }
        }
    }

    @Environment(\.colorScheme) var scheme

    private func channelButton(title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(AppTheme.Font.body)
                    .foregroundStyle(isOn.wrappedValue ? AppTheme.Colors.accent : Color.secondary)
                Text(title)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(isOn.wrappedValue ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn.wrappedValue ? AppTheme.Colors.accent.opacity(0.04) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
