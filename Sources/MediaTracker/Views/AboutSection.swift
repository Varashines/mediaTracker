import SwiftUI

struct AboutSection: View {
    @Environment(\.colorScheme) var scheme
    @State private var updateState: UpdateCheckResult = .checking
    @State private var showReleaseNotes = false
    @State private var releaseNotes = ""
    @State private var releaseURL = ""
    @State private var latestVersion = ""
    @State private var skippedVersion: String? = nil

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(text: "MediaTracker", icon: "info.circle.fill", color: .accentColor)

            SettingsCard(color: .accentColor) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Version \(appVersion)")
                                .font(AppTheme.Font.settingsRowTitle)
                                .foregroundStyle(.primary)
                            Text("Build \(buildNumber)")
                                .font(AppTheme.Font.settingsSubtitle)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "app.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(AppTheme.Colors.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    Rectangle()
                        .fill(AppTheme.Colors.strokeDefault(for: scheme))
                        .frame(height: 1)
                        .padding(.leading, 16)

                    SettingsRow(title: "Source Code", subtitle: "github.com/Varashines/mediaTracker", showDivider: false) {
                        Link(destination: URL(string: "https://github.com/Varashines/mediaTracker")!) {
                            Image(systemName: "arrow.up.right.square")
                                .font(AppTheme.Font.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("View on GitHub")
                    }
                }
            }

            SettingsSectionHeader(text: "Updates", icon: "arrow.triangle.2.circlepath", color: .blue)
            SettingsCard(color: .blue) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text("Latest Release")
                                    .font(AppTheme.Font.settingsRowTitle)
                                    .foregroundStyle(.primary)
                                statusBadge
                            }
                            Text(statusDescription)
                                .font(AppTheme.Font.settingsSubtitle)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if case .checking = updateState {} else {
                            SettingsButton(title: "Check Again") {
                                Task { await check() }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if case .success(let info) = updateState {
                        Rectangle()
                            .fill(AppTheme.Colors.strokeDefault(for: scheme))
                            .frame(height: 1)
                            .padding(.leading, 16)

                        VStack(alignment: .leading, spacing: 10) {
                            if info.isNewer {
                                Button {
                                    if let url = URL(string: info.url) {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(AppTheme.Font.body)
                                        Text("Download \(info.version)")
                                            .font(AppTheme.Font.caption)
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(AppTheme.Colors.accent)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            if let notes = info.notes {
                                Button {
                                    releaseNotes = notes
                                    releaseURL = info.url
                                    latestVersion = info.version
                                    showReleaseNotes = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.text")
                                            .font(AppTheme.Font.caption2)
                                        Text("Release Notes")
                                            .font(AppTheme.Font.caption)
                                    }
                                    .foregroundStyle(AppTheme.Colors.accent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .task {
            await check()
        }
        .sheet(isPresented: $showReleaseNotes) {
            releaseNotesSheet
        }
        .onAppear {
            skippedVersion = UserDefaults.standard.string(forKey: "skipped_version")
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch updateState {
        case .checking:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 14, height: 14)
        case .success(let info):
            if info.isNewer {
                StatusBadge(text: "Update Available", isActive: true)
            } else {
                StatusBadge(text: "Up to Date", isActive: true)
            }
        case .error:
            StatusBadge(text: "Check Failed", isActive: false)
        }
    }

    private var statusDescription: String {
        switch updateState {
        case .checking:
            "Checking for updates..."
        case .success(let info):
            if info.isNewer {
                "\(info.version) is available"
            } else {
                "You're running the latest version (\(info.version))"
            }
        case .error(let message):
            message
        }
    }

    private func check() async {
        updateState = .checking
        let result = await UpdateChecker.checkForUpdates()

        if case .success(let info) = result, info.isNewer {
            if let skipped = skippedVersion, info.version == skipped {
                updateState = .success(ReleaseInfo(
                    version: info.version,
                    url: info.url,
                    notes: info.notes,
                    isNewer: false
                ))
                return
            }
        }
        updateState = result
    }

    private var releaseNotesSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(latestVersion) Release Notes")
                    .font(AppTheme.Font.title3)
                Spacer()
                Button {
                    showReleaseNotes = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            ScrollView {
                Text(releaseNotes)
                    .font(AppTheme.Font.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            HStack {
                if latestVersion != "v\(appVersion)" && latestVersion != appVersion {
                    SettingsButton(title: "Skip This Version") {
                        skippedVersion = latestVersion
                        UserDefaults.standard.set(latestVersion, forKey: "skipped_version")
                        showReleaseNotes = false
                        if case .success(let info) = updateState {
                            updateState = .success(ReleaseInfo(
                                version: info.version,
                                url: info.url,
                                notes: info.notes,
                                isNewer: false
                            ))
                        }
                    }
                }

                Spacer()

                Button {
                    if let url = URL(string: releaseURL) {
                        NSWorkspace.shared.open(url)
                    }
                    showReleaseNotes = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("View on GitHub")
                    }
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppTheme.Colors.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .frame(width: 480, height: 400)
        .background(.ultraThinMaterial)
    }
}
