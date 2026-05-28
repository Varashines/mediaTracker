import SwiftUI
import SwiftData

struct VaultSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(text: "Backup", icon: "tray.and.arrow.down.fill", color: .blue)
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

            SettingsSectionHeader(text: "Maintenance", icon: "wrench.and.screwdriver.fill", color: .orange)
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

            SettingsSectionHeader(text: "Danger Zone", icon: "exclamationmark.triangle.fill", color: .red)
            GroupContainer(isDangerZone: true) {
                SettingsRow(title: "Delete All Data", subtitle: "Permanently wipe your entire library", showDivider: false) {
                    Button {
                        showClearConfirmation = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Delete")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.red.opacity(0.2), lineWidth: 0.5)
                        }
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
    }
}
