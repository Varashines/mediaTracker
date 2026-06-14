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
                apiKeyRow("TMDB", subtitle: "Movie & TV metadata", apiKey: $tmdbApiKey, showKey: $showTMDBKey, link: URL(string: "https://www.themoviedb.org/settings/api")!, showDivider: true)
                apiKeyRow("OMDb", subtitle: "Rotten Tomatoes scores", apiKey: $omdbApiKey, showKey: $showOMDBKey, link: URL(string: "https://www.omdbapi.com/apikey.aspx")!, showDivider: true)
                apiKeyRow("MooreMetrics", subtitle: "Show recommendations", apiKey: $mmApiKey, showKey: $showMMKey, link: URL(string: "https://www.mooremetrics.com")!, showDivider: false)
            }

            SettingsSectionHeader(text: "Notifications", icon: "bell.badge.fill", color: .red)

            SettingsCard(color: .red) {
                toggleRow("Enable Notifications", subtitle: "Get notified about new episodes and movies", isOn: $notificationsEnabled, showDivider: false)
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
                    Divider()
                        .overlay(AppTheme.Colors.strokeDefault(for: scheme))
                        .padding(.leading, 14)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Channels")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                channelButton("Movies", isOn: $movieNotificationsEnabled)
                                channelButton("TV Shows", isOn: $tvNotificationsEnabled)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider()
                        .overlay(AppTheme.Colors.strokeDefault(for: scheme))
                        .padding(.leading, 14)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delivery Time")
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("Daily notification schedule")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        DatePicker("", selection: Binding(
                            get: { Date(timeIntervalSince1970: notificationTime) },
                            set: { notificationTime = $0.timeIntervalSince1970.truncatingRemainder(dividingBy: TimeInterval.secondsInDay) }
                        ), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider()
                        .overlay(AppTheme.Colors.strokeDefault(for: scheme))
                        .padding(.leading, 14)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reschedule")
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("Refresh notification queue")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reschedule All") {
                            Task { await NotificationManager.shared.scheduleAllUpcomingNotifications() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.Colors.accent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func toggleRow(_ title: String, subtitle: String, isOn: Binding<Bool>, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
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

    private func apiKeyRow(_ name: String, subtitle: String, apiKey: Binding<String>, showKey: Binding<Bool>, link: URL, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(.primary)
                        StatusBadge(text: apiKey.wrappedValue.isEmpty ? "Missing" : "Connected", isActive: !apiKey.wrappedValue.isEmpty)
                    }
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Link(destination: link) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            HStack(spacing: 8) {
                ZStack(alignment: .trailing) {
                    if showKey.wrappedValue {
                        TextField("Enter API key...", text: apiKey)
                    } else {
                        SecureField("Enter API key...", text: apiKey)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .rounded))
                .padding(.vertical, 6)
                .padding(.leading, 10)
                .padding(.trailing, 30)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(AppTheme.Colors.strokeDefault(for: scheme), lineWidth: 0.5)
                )

                Button {
                    showKey.wrappedValue.toggle()
                } label: {
                    Image(systemName: showKey.wrappedValue ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

            if showDivider {
                Divider()
                    .overlay(AppTheme.Colors.strokeDefault(for: scheme))
                    .padding(.leading, 14)
            }
        }
    }

    private func channelButton(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(AppTheme.Animation.springSnappy) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isOn.wrappedValue ? AppTheme.Colors.accent : .secondary)
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(isOn.wrappedValue ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOn.wrappedValue ? AppTheme.Colors.accent.opacity(0.06) : Color.primary.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }
}
