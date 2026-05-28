import SwiftUI
import UserNotifications

struct ConnectSection: View {
    @AppStorage("tmdb_api_key") private var tmdbApiKey = ""
    @AppStorage("omdb_api_key") private var omdbApiKey = ""
    @AppStorage("notifications_enabled") private var notificationsEnabled = true
    @AppStorage("notifications_movies") private var movieNotificationsEnabled = true
    @AppStorage("notifications_tv") private var tvNotificationsEnabled = true
    @AppStorage("notifications_time") private var notificationTime: Double = 9 * 3600
    @State private var isPulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(text: "API Keys", color: .green)
            SettingsCard(color: .green) {
                apiRow(name: "TMDB", subtitle: "Movie & TV metadata", apiKey: $tmdbApiKey, isConnected: !tmdbApiKey.isEmpty, link: URL(string: "https://www.themoviedb.org/settings/api")!)
                apiRow(name: "OMDb", subtitle: "Rotten Tomatoes scores", apiKey: $omdbApiKey, isConnected: !omdbApiKey.isEmpty, link: URL(string: "https://www.omdbapi.com/apikey.aspx")!, showDivider: false)
            }

            SettingsSectionHeader(text: "Notifications", color: .red)
            SettingsCard(color: .red) {
                SettingsToggleRow(title: "Enable Notifications", subtitle: "Get notified about new episodes and movies", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if enabled {
                            NotificationManager.shared.requestPermission()
                            Task { await NotificationManager.shared.scheduleAllUpcomingNotifications() }
                        } else {
                            Task { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }
                        }
                    }

                if notificationsEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Channels")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 16)
                        HStack(spacing: 10) {
                            channelButton(title: "Movies", icon: "film", isOn: $movieNotificationsEnabled)
                            channelButton(title: "TV Shows", icon: "tv", isOn: $tvNotificationsEnabled)
                        }
                        .padding(.leading, 16)
                        .padding(.bottom, 8)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))

                    Divider().opacity(0.06).padding(.leading, 16)

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
                    Divider().opacity(0.06).padding(.leading, 16)

                    SettingsRow(title: "Reschedule", subtitle: "Refresh notification queue", showDivider: false) {
                        SettingsButton(title: "Reschedule All") {
                            Task { await NotificationManager.shared.scheduleAllUpcomingNotifications() }
                        }
                    }
                }
            }
        }
        .onAppear { isPulsing = true }
    }

    private func apiRow(name: String, subtitle: String, apiKey: Binding<String>, isConnected: Bool, link: URL, showDivider: Bool = true) -> some View {
        VStack(spacing: 0) {
            SettingsRow(title: name, subtitle: subtitle, showDivider: showDivider) {
                HStack(spacing: 8) {
                    StatusBadge(text: isConnected ? "Connected" : "Missing", isActive: isConnected)
                }
            }

            HStack(spacing: 8) {
                SecureField("Enter API key...", text: apiKey)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(Color.primary.opacity(0.02))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
                    .font(.system(size: 10, design: .monospaced))

                Link(destination: link) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Get \(name) API key")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            if showDivider {
                Divider().opacity(0.06).padding(.leading, 16)
            }
        }
    }

    private func channelButton(title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.secondary)
                Text(title)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(isOn.wrappedValue ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn.wrappedValue ? Color.accentColor.opacity(0.04) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
