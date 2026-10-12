import SwiftUI
import SwiftData

/// Modal preview displaying incoming titles, conflicting updates, pending uploads,
/// and affected TV show episode counts before performing a 2-way sync or backup.
struct SyncImpactSheet: View {
    let impact: CloudSyncService.SyncImpact
    let onConfirmSelectiveSync: (Set<String>, Set<String>, Set<String>, Bool) -> Void
    let onConfirmBackup: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedImportIDs: Set<String>
    @State private var selectedUpdateIDs: Set<String>
    @State private var selectedUploadIDs: Set<String>
    @State private var syncEpisodes: Bool = true
    @State private var activeTab: ImpactTab = .conflictsAndUpdates

    enum ImpactTab: String, CaseIterable {
        case conflictsAndUpdates = "Conflicts & Updates"
        case imports = "Incoming (Cloud)"
        case uploads = "Local (Upload)"
        case episodes = "Episodes"
    }

    init(
        impact: CloudSyncService.SyncImpact,
        onConfirmSelectiveSync: @escaping (Set<String>, Set<String>, Set<String>, Bool) -> Void,
        onConfirmBackup: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.impact = impact
        self.onConfirmSelectiveSync = onConfirmSelectiveSync
        self.onConfirmBackup = onConfirmBackup
        self.onDismiss = onDismiss
        _selectedImportIDs = State(initialValue: Set(impact.titlesToImport.map(\.id)))
        _selectedUpdateIDs = State(initialValue: Set(impact.titlesToUpdate.map(\.id)))
        _selectedUploadIDs = State(initialValue: Set(impact.titlesToUpload.map(\.id)))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: AppTheme.Spacing.small) {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.accent.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cloud Sync & Conflict Simulation")
                        .font(AppTheme.Font.title3)
                        .fontWeight(.bold)
                    Text("Review differences between your Mac and Supabase. Select what to synchronize.")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.vertical, AppTheme.Spacing.medium)
            .background(AppTheme.Colors.surface(for: colorScheme))

            Divider()

            // Segmented Tab Picker
            Picker("", selection: $activeTab) {
                Text("\(ImpactTab.conflictsAndUpdates.rawValue) (\(impact.titlesToUpdate.count))")
                    .tag(ImpactTab.conflictsAndUpdates)
                Text("\(ImpactTab.imports.rawValue) (\(impact.titlesToImport.count))")
                    .tag(ImpactTab.imports)
                Text("\(ImpactTab.uploads.rawValue) (\(impact.titlesToUpload.count))")
                    .tag(ImpactTab.uploads)
                Text("\(ImpactTab.episodes.rawValue) (\(impact.totalEpisodesToUpload + impact.totalEpisodesToImport))")
                    .tag(ImpactTab.episodes)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.vertical, AppTheme.Spacing.small)

            // Content Area
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    switch activeTab {
                    case .conflictsAndUpdates:
                        conflictsView
                    case .imports:
                        importsView
                    case .uploads:
                        uploadsView
                    case .episodes:
                        episodesView
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.large)
                .padding(.vertical, AppTheme.Spacing.small)
            }
            .frame(maxHeight: 420)

            Divider()

            // Bottom Actions Bar
            HStack(spacing: AppTheme.Spacing.medium) {
                Button {
                    onConfirmBackup()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "icloud.and.arrow.up.fill")
                        Text("Force Backup Mac to Cloud")
                    }
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Overwrites cloud with all 809 titles and 9,141 episodes from this Mac")

                Spacer()

                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    onConfirmSelectiveSync(selectedImportIDs, selectedUpdateIDs, selectedUploadIDs, syncEpisodes)
                } label: {
                    Text("Sync Selected Changes")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.vertical, AppTheme.Spacing.medium)
            .background(AppTheme.Colors.surface(for: colorScheme))
        }
        .frame(width: 680)
        .background(AppTheme.Colors.background(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Tab Views

    private var conflictsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if impact.titlesToUpdate.isEmpty {
                emptyState(title: "No State Conflicts", message: "All shared titles have identical status and taste ratings.")
            } else {
                Text("The following titles exist on both Mac and Cloud, but their status or taste values differ:")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)

                ForEach(impact.titlesToUpdate) { item in
                    let isChecked = selectedUpdateIDs.contains(item.id)
                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(
                            get: { isChecked },
                            set: { if $0 { selectedUpdateIDs.insert(item.id) } else { selectedUpdateIDs.remove(item.id) } }
                        ))
                        .toggleStyle(.checkbox)

                        posterThumb(url: item.posterURL)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(AppTheme.Font.bodyBold)
                            HStack(spacing: 6) {
                                Text("Mac: \(item.state) (\(item.taste))")
                                    .font(AppTheme.Font.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppTheme.Colors.surfaceMuted(for: colorScheme))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                Text("Cloud: \(item.conflictCloudState ?? "-") (\(item.conflictCloudTaste ?? "-"))")
                                    .font(AppTheme.Font.caption)
                                    .foregroundStyle(Color.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }

                        Spacer()
                    }
                    .padding(10)
                    .background(AppTheme.Colors.surface(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var importsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if impact.titlesToImport.isEmpty {
                emptyState(title: "No Incoming Titles", message: "No new titles found in Cloud that are missing from your Mac.")
            } else {
                Text("These titles exist in your Cloud backup but haven't been added to this Mac:")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)

                ForEach(impact.titlesToImport) { item in
                    let isChecked = selectedImportIDs.contains(item.id)
                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(
                            get: { isChecked },
                            set: { if $0 { selectedImportIDs.insert(item.id) } else { selectedImportIDs.remove(item.id) } }
                        ))
                        .toggleStyle(.checkbox)

                        posterThumb(url: item.posterURL)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(AppTheme.Font.bodyBold)
                            Text("Type: \(item.type) • Status: \(item.state) • Taste: \(item.taste)")
                                .font(AppTheme.Font.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("Download")
                            .font(AppTheme.Font.smallBold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.Colors.accent.opacity(0.15))
                            .foregroundStyle(AppTheme.Colors.accent)
                            .clipShape(Capsule())
                    }
                    .padding(10)
                    .background(AppTheme.Colors.surface(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var uploadsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if impact.titlesToUpload.isEmpty {
                emptyState(title: "No Pending Uploads", message: "All local Mac titles are already present in the Cloud.")
            } else {
                HStack {
                    Text("Modified or new titles on this Mac that will upload to Cloud:")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Select All") {
                        selectedUploadIDs = Set(impact.titlesToUpload.map(\.id))
                    }
                    .font(AppTheme.Font.caption)
                }

                ForEach(impact.titlesToUpload.prefix(100)) { item in
                    let isChecked = selectedUploadIDs.contains(item.id)
                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(
                            get: { isChecked },
                            set: { if $0 { selectedUploadIDs.insert(item.id) } else { selectedUploadIDs.remove(item.id) } }
                        ))
                        .toggleStyle(.checkbox)

                        posterThumb(url: item.posterURL)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(AppTheme.Font.bodyBold)
                            Text("\(item.type) • \(item.state) • \(item.taste)")
                                .font(AppTheme.Font.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("Upload")
                            .font(AppTheme.Font.smallBold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(Color.green)
                            .clipShape(Capsule())
                    }
                    .padding(10)
                    .background(AppTheme.Colors.surface(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if impact.titlesToUpload.count > 100 {
                    Text("+ \(impact.titlesToUpload.count - 100) more local titles selected for initial upload")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var episodesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $syncEpisodes) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Synchronize TV Episode Watch Progress")
                        .font(AppTheme.Font.bodyBold)
                    Text("Reconcile watched state for all TV show episodes between Mac and Cloud")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Divider()

            if impact.episodesToUploadShows.isEmpty && impact.episodesToImportShows.isEmpty {
                emptyState(title: "Episodes In Sync", message: "All TV episodes on this Mac match the Cloud watch progress.")
            } else {
                Text("Watched TV episodes that will be updated in the Cloud:")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(impact.episodesToUploadShows) { show in
                        HStack(spacing: 10) {
                            posterThumb(url: show.posterURL)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(show.title)
                                    .font(AppTheme.Font.caption)
                                    .lineLimit(1)
                                Text("\(show.episodeCount) watched episodes")
                                    .font(AppTheme.Font.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(AppTheme.Colors.surface(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    // MARK: - Helper Views

    private func posterThumb(url: String?) -> some View {
        CachedImage(url: url.flatMap(URL.init), targetSize: CGSize(width: 32, height: 48)) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 32, height: 48)
                .overlay {
                    Image(systemName: "film")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
        }
        .frame(width: 32, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.green)
            Text(title)
                .font(AppTheme.Font.bodyBold)
            Text(message)
                .font(AppTheme.Font.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}
