import SwiftUI
import SwiftData

struct VaultSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(text: "Backup", color: .blue)
            SettingsCard(color: .blue) {
                SettingsRow(title: "Export Library", subtitle: "Save a backup of your collection", showDivider: true) {
                    SettingsButton(title: "Export") {
                        let container = modelContext.container
                        Task {
                            let context = ModelContext(container)
                            let descriptor = FetchDescriptor<MediaItem>(sortBy: [SortDescriptor(\.title)])
                            if let items = try? context.fetch(descriptor) {
                                await MainActor.run { LibraryImportExportService.shared.exportLibrary(items: items) }
                            }
                        }
                    }
                }
                SettingsRow(title: "Import Library", subtitle: "Restore from a backup file", showDivider: true) {
                    SettingsButton(title: "Import") {
                        LibraryImportExportService.shared.importLibrary(modelContext: modelContext)
                    }
                }
                SettingsRow(title: "Auto Backups", subtitle: "View automatic backup folder", showDivider: false) {
                    SettingsButton(title: "Show in Finder") {
                        let url = URL.applicationSupportDirectory.appendingPathComponent("AutoBackups")
                        if !FileManager.default.fileExists(atPath: url.path) {
                            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        }
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                    }
                }
            }

            SettingsSectionHeader(text: "Maintenance", color: .orange)
            SettingsCard(color: .orange) {
                SettingsRow(title: "Database Repair", subtitle: "Fix relationships and remove duplicates", showDivider: true) {
                    SettingsButton(title: "Repair") {
                        DataService.shared.runMaintenance(modelContext: modelContext)
                    }
                }
                SettingsRow(title: "Image Cache", subtitle: "Clear downloaded poster images", showDivider: false) {
                    SettingsButton(title: "Purge") {
                        ImageCache.shared.clearFullCache()
                    }
                }
            }

            SettingsSectionHeader(text: "Danger Zone", color: .red)
            SettingsCard(color: .red) {
                Button {
                    showClearConfirmation = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Delete All Data")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.red)
                            Text("Permanently wipe your entire library")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .confirmationDialog("Delete Everything?", isPresented: $showClearConfirmation) {
            Button("Delete All Library Data", role: .destructive) {
                DataService.shared.clearDatabase(modelContext: modelContext)
            }
        }
    }
}
