import SwiftUI
import SwiftData

/// Modal preview of what a two-way sync or a full backup would change.
///
/// Laid out as a sidebar of categories next to one detail pane, rather than a segmented
/// control: six segments never fit the sheet width (labels truncated), and the categories
/// are stable enough to be a list. Heights are fixed so the sheet keeps one size no matter
/// how many rows a category has.
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
    @State private var section: SyncSection = .conflicts

    private enum SyncSection: String, CaseIterable, Identifiable {
        case conflicts, incoming, uploads, episodes, collections, history

        var id: String { rawValue }

        var title: String {
            switch self {
            case .conflicts: return "Conflicts"
            case .incoming: return "Incoming"
            case .uploads: return "Uploads"
            case .episodes: return "Episodes"
            case .collections: return "Collections"
            case .history: return "History"
            }
        }

        var systemImage: String {
            switch self {
            case .conflicts: return "exclamationmark.triangle"
            case .incoming: return "arrow.down.circle"
            case .uploads: return "arrow.up.circle"
            case .episodes: return "play.rectangle.on.rectangle"
            case .collections: return "square.stack.3d.up"
            case .history: return "clock.arrow.circlepath"
            }
        }

        var blurb: String {
            switch self {
            case .conflicts:
                return "Titles held by both sides that disagree on status or taste. Newest edit wins."
            case .incoming:
                return "Titles the cloud has that this Mac doesn't yet."
            case .uploads:
                return "Titles this Mac edited that the cloud hasn't seen."
            case .episodes:
                return "Watched TV episodes to reconcile."
            case .collections:
                return "Collections and their membership, synced in both directions."
            case .history:
                return "The per-viewing log behind rewatching, streaks and year in review."
            }
        }
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
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 218)
                Divider()
                ScrollView {
                    sectionDetail
                        .padding(AppTheme.Spacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 392)
            Divider()
            footer
        }
        .frame(width: 780)
        .background(AppTheme.Colors.background(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.smallMedium) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Cloud Sync")
                    .font(AppTheme.Font.title3)
                Text(subtitle)
                    .font(AppTheme.Font.settingsSubtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: AppTheme.Spacing.small)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, AppTheme.Spacing.large)
        .padding(.vertical, AppTheme.Spacing.smallMedium)
        .background(AppTheme.Colors.surface(for: colorScheme))
    }

    private var subtitle: String {
        if let error = impact.errorDescription { return error }
        guard impact.hasChanges else { return "No title changes to review — episodes and history still sync." }
        return "\(impact.totalChanges) changes to review between this Mac and Supabase."
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
            ForEach(SyncSection.allCases) { item in
                sidebarRow(item)
            }
            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.tiny)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppTheme.Colors.surfaceMuted(for: colorScheme))
    }

    private func sidebarRow(_ item: SyncSection) -> some View {
        let count = count(for: item)
        let isSelected = section == item

        return Button {
            section = item
        } label: {
            HStack(spacing: AppTheme.Spacing.tiny) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(count > 0 ? AppTheme.Colors.accent : .secondary)
                    .frame(width: 16)

                Text(item.title)
                    .font(AppTheme.Font.settingsRowTitle)
                    .foregroundStyle(.primary)

                Spacer(minLength: AppTheme.Spacing.micro)

                Text("\(count)")
                    .font(AppTheme.Font.caption2)
                    .foregroundStyle(count > 0 ? AppTheme.Colors.accent : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(
                            count > 0
                                ? AppTheme.Colors.accent.opacity(0.14)
                                : Color.secondary.opacity(0.10)
                        )
                    )
            }
            .padding(.horizontal, AppTheme.Spacing.tiny)
            .padding(.vertical, AppTheme.Spacing.mini)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                    .fill(isSelected ? AppTheme.Colors.surface(for: colorScheme) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func count(for item: SyncSection) -> Int {
        switch item {
        case .conflicts: return impact.titlesToUpdate.count
        case .incoming: return impact.titlesToImport.count
        case .uploads: return impact.titlesToUpload.count
        case .episodes: return impact.totalEpisodesToImport + impact.totalEpisodesToUpload
        case .collections: return impact.collectionsToImport.count + impact.collectionsToUpload.count
        case .history: return impact.cyclesToUpload + impact.eventsToUpload
        }
    }

    // MARK: - Detail

    private var sectionDetail: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smallMedium) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.tiny) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.accent)
                Text(section.title)
                    .font(AppTheme.Font.heading)
            }
            Text(section.blurb)
                .font(AppTheme.Font.settingsSubtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Group {
                switch section {
                case .conflicts: conflictsDetail
                case .incoming: incomingDetail
                case .uploads: uploadsDetail
                case .episodes: episodesDetail
                case .collections: collectionsDetail
                case .history: historyDetail
                }
            }
            .padding(.top, AppTheme.Spacing.micro)
        }
    }

    private var conflictsDetail: some View {
        Group {
            if impact.titlesToUpdate.isEmpty {
                emptyState(title: "No Conflicts", message: "Every shared title already agrees on status and taste.")
            } else {
                VStack(spacing: AppTheme.Spacing.mini) {
                    ForEach(impact.titlesToUpdate) { item in
                        titleRow(
                            title: item.title,
                            subtitle: "Mac: \(item.state) (\(item.taste))  →  Cloud: \(item.conflictCloudState ?? "-") (\(item.conflictCloudTaste ?? "-"))",
                            posterURL: item.posterURL,
                            badgeText: "Cloud wins",
                            badgeColor: .orange,
                            isOn: binding(for: item.id, in: $selectedUpdateIDs)
                        )
                    }
                }
                Text("Checked titles adopt the cloud's version. Uncheck to leave this Mac as it is.")
                    .font(AppTheme.Font.settingsSubtitle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var incomingDetail: some View {
        Group {
            if impact.titlesToImport.isEmpty {
                emptyState(title: "Nothing Incoming", message: "No cloud titles are missing from this Mac.")
            } else {
                VStack(spacing: AppTheme.Spacing.mini) {
                    ForEach(impact.titlesToImport) { item in
                        titleRow(
                            title: item.title,
                            subtitle: "\(item.type) • \(item.state) • \(item.taste)",
                            posterURL: item.posterURL,
                            badgeText: "Download",
                            badgeColor: AppTheme.Colors.accent,
                            isOn: binding(for: item.id, in: $selectedImportIDs)
                        )
                    }
                }
            }
        }
    }

    private var uploadsDetail: some View {
        Group {
            if impact.titlesToUpload.isEmpty {
                emptyState(title: "Nothing to Upload", message: "Every local title is already in the cloud.")
            } else {
                HStack {
                    Text("\(impact.titlesToUpload.count) local titles will upload.")
                        .font(AppTheme.Font.settingsSubtitle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Select All") {
                        selectedUploadIDs = Set(impact.titlesToUpload.map(\.id))
                    }
                    .font(AppTheme.Font.caption)
                    Button("Clear") {
                        selectedUploadIDs = []
                    }
                    .font(AppTheme.Font.caption)
                }

                VStack(spacing: AppTheme.Spacing.mini) {
                    ForEach(impact.titlesToUpload.prefix(100)) { item in
                        titleRow(
                            title: item.title,
                            subtitle: "\(item.type) • \(item.state) • \(item.taste)",
                            posterURL: item.posterURL,
                            badgeText: "Upload",
                            badgeColor: .green,
                            isOn: binding(for: item.id, in: $selectedUploadIDs)
                        )
                    }
                }

                if impact.titlesToUpload.count > 100 {
                    Text("+ \(impact.titlesToUpload.count - 100) more selected titles")
                        .font(AppTheme.Font.settingsSubtitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var episodesDetail: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smallMedium) {
            Toggle(isOn: $syncEpisodes) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reconcile episode progress")
                        .font(AppTheme.Font.bodyBold)
                    Text("Watched state for every TV episode, both directions.")
                        .font(AppTheme.Font.settingsSubtitle)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            if impact.episodesToUploadShows.isEmpty && impact.episodesToImportShows.isEmpty {
                emptyState(title: "Episodes In Sync", message: "Every TV episode matches the cloud.")
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: AppTheme.Spacing.tiny), GridItem(.flexible(), spacing: AppTheme.Spacing.tiny)],
                    spacing: AppTheme.Spacing.tiny
                ) {
                    ForEach(impact.episodesToUploadShows) { show in
                        episodeShowRow(show, label: "to cloud")
                    }
                    ForEach(impact.episodesToImportShows) { show in
                        episodeShowRow(show, label: "from cloud")
                    }
                }
            }
        }
    }

    private func episodeShowRow(_ show: CloudSyncService.ImpactEpisodeShow, label: String) -> some View {
        HStack(spacing: AppTheme.Spacing.tiny) {
            posterThumb(url: show.posterURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(show.title)
                    .font(AppTheme.Font.body)
                    .lineLimit(1)
                Text("\(show.episodeCount) watched \(label)")
                    .font(AppTheme.Font.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.tiny)
        .background(AppTheme.Colors.surface(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
    }

    private var collectionsDetail: some View {
        Group {
            if impact.collectionsToUpload.isEmpty && impact.collectionsToImport.isEmpty {
                emptyState(title: "No Collection Changes", message: "Collections already match on both sides.")
            } else {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.smallMedium) {
                    if !impact.collectionsToUpload.isEmpty {
                        collectionGroup(title: "This Mac → Cloud", items: impact.collectionsToUpload, systemImage: "arrow.up.circle")
                    }
                    if !impact.collectionsToImport.isEmpty {
                        collectionGroup(title: "Cloud → This Mac", items: impact.collectionsToImport, systemImage: "arrow.down.circle")
                    }
                }
            }
        }
    }

    private func collectionGroup(
        title: String,
        items: [CloudSyncService.ImpactCollection],
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.mini) {
            HStack(spacing: AppTheme.Spacing.mini) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.accent)
                Text("\(title) (\(items.count))")
                    .font(AppTheme.Font.caption)
            }
            ForEach(items) { collection in
                HStack(spacing: AppTheme.Spacing.tiny) {
                    Image(systemName: "rectangle.stack")
                        .foregroundStyle(.secondary)
                    Text(collection.name)
                        .font(AppTheme.Font.body)
                    Spacer(minLength: AppTheme.Spacing.tiny)
                    Text("\(collection.itemCount) \(collection.itemCount == 1 ? "title" : "titles")")
                        .font(AppTheme.Font.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppTheme.Spacing.small)
                .padding(.vertical, AppTheme.Spacing.tiny)
                .background(AppTheme.Colors.surface(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
            }
        }
    }

    private var historyDetail: some View {
        Group {
            if impact.cyclesToUpload == 0 && impact.eventsToUpload == 0 {
                emptyState(title: "History In Sync", message: "The cloud's viewing log is already up to date.")
            } else {
                statRow(
                    systemImage: "clock.arrow.circlepath",
                    title: "This Mac → Cloud",
                    detail: "\(impact.cyclesToUpload) cycles · \(impact.eventsToUpload) events"
                )
            }
        }
    }

    // MARK: - Rows

    private func titleRow(
        title: String,
        subtitle: String,
        posterURL: String?,
        badgeText: String,
        badgeColor: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Toggle("", isOn: isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()

            posterThumb(url: posterURL)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTheme.Font.bodyBold)
                    .lineLimit(1)
                Text(subtitle)
                    .font(AppTheme.Font.settingsSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: AppTheme.Spacing.tiny)

            Text(badgeText)
                .font(AppTheme.Font.caption2)
                .foregroundStyle(badgeColor)
                .padding(.horizontal, AppTheme.Spacing.tiny)
                .padding(.vertical, 3)
                .background(Capsule().fill(badgeColor.opacity(0.14)))
        }
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.vertical, AppTheme.Spacing.tiny)
        .background(AppTheme.Colors.surface(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
    }

    private func statRow(systemImage: String, title: String, detail: String) -> some View {
        HStack(spacing: AppTheme.Spacing.tiny) {
            Image(systemName: systemImage).foregroundStyle(AppTheme.Colors.accent)
            Text(title)
                .font(AppTheme.Font.caption)
            Spacer(minLength: AppTheme.Spacing.tiny)
            Text(detail)
                .font(AppTheme.Font.settingsSubtitle)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.vertical, AppTheme.Spacing.compact)
        .background(AppTheme.Colors.surface(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
    }

    private func posterThumb(url: String?) -> some View {
        CachedImage(url: url.flatMap(URL.init), targetSize: CGSize(width: 32, height: 48)) {
            RoundedRectangle(cornerRadius: AppTheme.Radius.micro)
                .fill(Color.secondary.opacity(0.2))
                .overlay {
                    Image(systemName: "film")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
        }
        .frame(width: 32, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.micro))
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.mini) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color.green)
            Text(title)
                .font(AppTheme.Font.bodyBold)
            Text(message)
                .font(AppTheme.Font.settingsSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.large)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Button {
                onConfirmBackup()
            } label: {
                HStack(spacing: AppTheme.Spacing.mini) {
                    Image(systemName: "icloud.and.arrow.up.fill")
                    Text("Force Backup Mac to Cloud")
                }
                .font(AppTheme.Font.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, AppTheme.Spacing.compact)
                .padding(.vertical, AppTheme.Spacing.mini)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                        .fill(Color.orange.opacity(0.12))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Overwrites the cloud with this Mac's whole library — every title, watched episode, collection and history row.")

            if impact.hasChanges {
                Text("\(selectedCount) of \(impact.totalChanges) selected")
                    .font(AppTheme.Font.settingsSubtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: AppTheme.Spacing.small)

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
        .padding(.vertical, AppTheme.Spacing.smallMedium)
        .background(AppTheme.Colors.surface(for: colorScheme))
    }

    private var selectedCount: Int {
        selectedImportIDs.count + selectedUpdateIDs.count + selectedUploadIDs.count
    }

    private func binding(for id: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { isOn in
                if isOn { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) }
            }
        )
    }
}
