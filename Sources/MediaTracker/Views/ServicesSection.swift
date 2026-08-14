import SwiftUI
import UserNotifications

struct ServicesSection: View {
    @State private var tmdbApiKey: String
    @State private var omdbApiKey: String
    @State private var mmApiKey: String
    @AppStorage("notifications_enabled") private var notificationsEnabled = true
    @AppStorage("notifications_movies") private var movieNotificationsEnabled = true
    @AppStorage("notifications_tv") private var tvNotificationsEnabled = true
    @AppStorage("notifications_time") private var notificationTime: Double = 9 * 3600

    @State private var showTMDBKey = false
    @State private var showOMDBKey = false
    @State private var showMMKey = false
    @State private var tmdbValidation: KeyValidationState = .idle
    @State private var omdbValidation: KeyValidationState = .idle
    @Environment(\.colorScheme) var scheme

    init() {
        _tmdbApiKey = State(initialValue: KeychainStore.read(UserDefaultsKeys.tmdbAPIKey.rawValue) ?? "")
        _omdbApiKey = State(initialValue: KeychainStore.read(UserDefaultsKeys.omdbAPIKey.rawValue) ?? "")
        _mmApiKey = State(initialValue: KeychainStore.read(UserDefaultsKeys.mmAPIKey.rawValue) ?? "")
    }

    enum KeyValidationState: Equatable {
        case idle
        case testing
        case valid
        case invalid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            SettingsCard(color: .green) {
                VStack(spacing: 0) {
                    apiKeyRow("TMDB", subtitle: "Movie & TV metadata", binding: $tmdbApiKey, showKey: $showTMDBKey, link: "https://www.themoviedb.org/settings/api", validation: $tmdbValidation) {
                        await APIClient.shared.validateTMDBKey(key: tmdbApiKey)
                    }
                    .onChange(of: tmdbApiKey) { _, newValue in
                        persist(newValue, for: .tmdbAPIKey)
                    }
                    apiKeyRow("OMDb", subtitle: "Rotten Tomatoes scores", binding: $omdbApiKey, showKey: $showOMDBKey, link: "https://www.omdbapi.com/apikey.aspx", validation: $omdbValidation) {
                        await APIClient.shared.validateOMDBKey(key: omdbApiKey)
                    }
                    .onChange(of: omdbApiKey) { _, newValue in
                        persist(newValue, for: .omdbAPIKey)
                    }
                    apiKeyRow("MooreMetrics", subtitle: "Show recommendations", binding: $mmApiKey, showKey: $showMMKey, link: "https://www.mooremetrics.com", validation: nil)
                    .onChange(of: mmApiKey) { _, newValue in
                        persist(newValue, for: .mmAPIKey)
                    }
                }
            }

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
                        SettingsLabeledRow(title: "Channels", subtitle: nil, showDivider: true) {
                            HStack(spacing: AppTheme.Spacing.tiny) {
                                channelChip("Movies", isOn: $movieNotificationsEnabled)
                                channelChip("TV Shows", isOn: $tvNotificationsEnabled)
                            }
                        }

                        SettingsLabeledRow(title: "Delivery Time", subtitle: nil, showDivider: true) {
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

    private func persist(_ value: String, for key: UserDefaultsKeys) {
        if value.isEmpty {
            KeychainStore.delete(key.rawValue)
        } else {
            KeychainStore.write(value, forKey: key.rawValue)
        }
    }

    private func apiKeyRow(_ name: String, subtitle: String, binding: Binding<String>, showKey: Binding<Bool>, link: String, validation: Binding<KeyValidationState>?, testAction: (() async -> Bool)? = nil) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.small) {
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
                    .frame(width: 180)
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
                    .contentShape(Circle())
                    .accessibilityLabel(showKey.wrappedValue ? "Hide API key" : "Show API key")

                    if let validation, let testAction {
                        let state = validation.wrappedValue
                        if state != .idle {
                            Image(systemName: state == .valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(AppTheme.Font.caption)
                                .foregroundStyle(state == .valid ? .green : .red)
                                .help(state == .valid ? "Key is valid" : "Key could not be validated")
                        }

                        Button {
                            guard !binding.wrappedValue.isEmpty else { return }
                            validation.wrappedValue = .testing
                            Task {
                                let isValid = await testAction()
                                await MainActor.run {
                                    validation.wrappedValue = isValid ? .valid : .invalid
                                }
                            }
                        } label: {
                            if validation.wrappedValue == .testing {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "checkmark.seal")
                                    .font(AppTheme.Font.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                        .disabled(binding.wrappedValue.isEmpty || validation.wrappedValue == .testing)
                        .accessibilityLabel("Test \(name) API key")
                    }

                    Link(destination: URL(string: link)!) {
                        Image(systemName: "arrow.up.right.square")
                            .font(AppTheme.Font.label)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .help("Get a \(name) API key")
                }
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)
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
                    .foregroundStyle(isOn.wrappedValue ? .secondary : .secondary)
                Text(title)
                    .font(AppTheme.Font.label)
                    .foregroundStyle(isOn.wrappedValue ? .primary : .secondary)
            }
            .padding(.horizontal, AppTheme.Spacing.tiny)
            .padding(.vertical, AppTheme.Spacing.micro)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(isOn.wrappedValue ? .secondary.opacity(0.06) : Color.primary.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}
