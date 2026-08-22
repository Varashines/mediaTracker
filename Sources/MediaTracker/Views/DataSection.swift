import SwiftUI
import SwiftData

struct DataSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var scheme
    @State private var showClearConfirmation = false
    @State private var exportData: Data?
    @State private var showExportDialog = false
    @State private var showImportSheet = false
    @State private var backupCount = 0
    @State private var lastBackupDate: Date?

    private var backupSubtitle: String {
        if backupCount == 0 {
            return "No automatic backups yet"
        }
        if let date = lastBackupDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "\(backupCount) backups · Last: \(formatter.string(from: date))"
        }
        return "\(backupCount) backups stored"
    }

    private var backgroundManager: BackgroundTaskManager {
        BackgroundTaskManager.shared
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            SettingsCard(color: .blue) {
                VStack(spacing: 0) {
                    SettingsRow(title: "Export Library", subtitle: "Save a JSON backup of your collection", showDivider: true) {
                        SettingsButton(title: "Export") {
                            let container = modelContext.container
                            Task {
                                let context = ModelContext(container)
                                let descriptor = FetchDescriptor<MediaItem>(sortBy: [SortDescriptor(\.title)])
                                do {
                                    let items = try context.fetch(descriptor)
                                    let exportItems = LibraryImportExportService.shared.prepareExportData(items: items, context: context)
                                    exportData = exportItems
                                    showExportDialog = true
                                } catch {
                                    AppErrorState.shared.surfaceError("Export failed: \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                    SettingsRow(title: "Import Library", subtitle: "Restore from a MediaTracker backup file", showDivider: true) {
                        SettingsButton(title: "Import Wizard...") {
                            showImportSheet = true
                        }
                    }
                    SettingsRow(title: "Auto Backups", subtitle: backupSubtitle, showDivider: false) {
                        SettingsButton(title: "Show in Finder") {
                            let url = URL.applicationSupportDirectory.appendingPathComponent("AutoBackups")
                            if !FileManager.default.fileExists(atPath: url.path) {
                                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                            }
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                        }
                    }
                }
            }

            SettingsCard(color: .teal) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Background Task Queue")
                                .font(AppTheme.Font.bodyMedium)
                                .foregroundStyle(.primary)
                            if let activeTask = backgroundManager.activeTaskDescription {
                                Text(activeTask)
                                    .font(AppTheme.Font.caption)
                                    .foregroundStyle(AppTheme.Colors.accent)
                            } else {
                                Text("All background tasks idle")
                                    .font(AppTheme.Font.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if backgroundManager.isImportActive {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(AppTheme.Spacing.medium)
            }

            SettingsCard(color: .orange) {
                VStack(spacing: 0) {
                    SettingsRow(title: "Database Repair", subtitle: "Fix relationships and remove duplicates", showDivider: true) {
                        if DataService.shared.isRunningMaintenance {
                            ProgressView()
                                .controlSize(.small)
                                .help("Repair in progress…")
                        } else {
                            SettingsButton(title: "Repair") {
                                DataService.shared.runMaintenance(modelContext: modelContext)
                            }
                        }
                    }
                    SettingsRow(title: "Image Cache", subtitle: "Clear downloaded poster images", showDivider: false) {
                        SettingsButton(title: "Purge") {
                            ImageCache.shared.clearFullCache()
                            AppErrorState.shared.showToast("Image cache cleared.", style: .success)
                        }
                    }
                }
            }

            GroupContainer(isDangerZone: true) {
                SettingsRow(title: "Delete All Data", subtitle: "Permanently wipe your entire library", showDivider: false) {
                    SettingsButton(title: "Delete", color: .red) {
                        showClearConfirmation = true
                    }
                }
            }
        }
        .sheet(isPresented: $showImportSheet) {
            ImportWizardSheet()
        }
        .onAppear {
            let info = LibraryImportExportService.autoBackupInfo()
            backupCount = info.count
            lastBackupDate = info.lastDate
        }
        .confirmationDialog("Delete Everything?", isPresented: $showClearConfirmation) {
            Button("Delete All Library Data", role: .destructive) {
                DataService.shared.clearDatabase(modelContext: modelContext)
            }
        } message: {
            Text("Permanently deletes every item, collection, and cached image. This cannot be undone — export a backup first if you might want your data later.")
        }
        .fileExporter(isPresented: $showExportDialog, document: exportData.map { JSONFileDocument(data: $0) }, contentType: .json, defaultFilename: "MediaTracker_Backup") { result in
            if case .failure(let error) = result {
                AppErrorState.shared.surfaceError("Export failed: \(error.localizedDescription)")
            }
            exportData = nil
        }
    }
}
