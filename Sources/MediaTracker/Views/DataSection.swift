import SwiftUI
import SwiftData

struct DataSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var scheme
    @State private var showClearConfirmation = false
    @State private var exportData: Data?
    @State private var showExportDialog = false
    @State private var showImportDialog = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            SettingsSectionHeader(text: "Backup", icon: "tray.and.arrow.down.fill", color: .blue)

            SettingsCard(color: .blue) {
                actionRow("Export Library", subtitle: "Save a backup of your collection", button: "Export") {
                    let container = modelContext.container
                    Task {
                        let context = ModelContext(container)
                        let descriptor = FetchDescriptor<MediaItem>(sortBy: [SortDescriptor(\.title)])
                        if let items = try? context.fetch(descriptor) {
                            let exportItems = LibraryImportExportService.shared.prepareExportData(items: items)
                            exportData = exportItems
                            showExportDialog = true
                        }
                    }
                }
                Divider().overlay(AppTheme.Colors.strokeDefault(for: scheme)).padding(.leading, 14)
                actionRow("Import Library", subtitle: "Restore from a backup file", button: "Import") {
                    showImportDialog = true
                }
                Divider().overlay(AppTheme.Colors.strokeDefault(for: scheme)).padding(.leading, 14)
                actionRow("Auto Backups", subtitle: "View automatic backup folder", button: "Show in Finder") {
                    let url = URL.applicationSupportDirectory.appendingPathComponent("AutoBackups")
                    if !FileManager.default.fileExists(atPath: url.path) {
                        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    }
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                }
            }

            SettingsSectionHeader(text: "Maintenance", icon: "wrench.and.screwdriver.fill", color: .orange)

            SettingsCard(color: .orange) {
                actionRow("Database Repair", subtitle: "Fix relationships and remove duplicates", button: "Repair") {
                    DataService.shared.runMaintenance(modelContext: modelContext)
                }
                Divider().overlay(AppTheme.Colors.strokeDefault(for: scheme)).padding(.leading, 14)
                actionRow("Image Cache", subtitle: "Clear downloaded poster images", button: "Purge") {
                    ImageCache.shared.clearFullCache()
                }
            }

            SettingsSectionHeader(text: "Danger Zone", icon: "exclamationmark.triangle.fill", color: .red)

            GroupContainer(isDangerZone: true) {
                SettingsRow(title: "Delete All Data", subtitle: "Permanently wipe your entire library", showDivider: false) {
                    Button {
                        showClearConfirmation = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(AppTheme.Font.caption)
                            Text("Delete")
                                .font(AppTheme.Font.caption)
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .confirmationDialog("Delete Everything?", isPresented: $showClearConfirmation) {
            Button("Delete All Library Data", role: .destructive) {
                DataService.shared.clearDatabase(modelContext: modelContext)
            }
        }
        .fileExporter(isPresented: $showExportDialog, document: exportData.map { JSONFileDocument(data: $0) }, contentType: .json, defaultFilename: "MediaTracker_Backup") { result in
            if case .failure(let error) = result {
                AppErrorState.shared.surfaceError("Export failed: \(error.localizedDescription)")
            }
            exportData = nil
        }
        .fileImporter(isPresented: $showImportDialog, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let container = modelContext.container
                Task.detached(priority: .userInitiated) {
                    do {
                        let data = try Data(contentsOf: url)
                        let backup = try JSONDecoder().decode(LibraryBackup.self, from: data)
                        let count = await BackgroundDataService.importLibraryData(backup: backup, modelContainer: container)
                        await MainActor.run {
                            AppErrorState.shared.showToast("Imported \(count) items.", style: .success)
                            let context = ModelContext(container)
                            let descriptor = FetchDescriptor<MediaItem>()
                            if let allItems = try? context.fetch(descriptor) {
                                DataService.shared.refreshMetadata(for: allItems, modelContext: context, force: false)
                            }
                            DataService.shared.runMaintenance(modelContext: context, silent: true)
                        }
                    } catch {
                        await MainActor.run {
                            AppErrorState.shared.surfaceError("Import failed: \(error.localizedDescription)")
                        }
                    }
                }
            case .failure(let error):
                AppErrorState.shared.surfaceError("Import cancelled: \(error.localizedDescription)")
            }
        }
    }

    private func actionRow(_ title: String, subtitle: String, button: String, action: @escaping () -> Void) -> some View {
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
            Button(button) {
                action()
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
