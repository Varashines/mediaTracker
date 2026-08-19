import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportWizardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    enum WizardStep {
        case selectFile
        case preview
        case strategy
        case progress
        case summary
    }

    @State private var currentStep: WizardStep = .selectFile
    @State private var backupData: LibraryBackup?
    @State private var existingMatchCount: Int = 0
    @State private var newItemsCount: Int = 0
    @State private var selectedStrategy: ImportConflictStrategy = .merge
    @State private var progressInfo: ImportProgress?
    @State private var importTask: Task<Void, Never>?
    @State private var isAnalyzing: Bool = false
    @State private var errorMessage: String?
    @State private var showFileImporter: Bool = false

    private var stepProgress: (current: Int, total: Int) {
        let current: Int
        switch currentStep {
        case .selectFile: current = 1
        case .preview: current = 2
        case .strategy: current = 3
        case .progress: current = 4
        case .summary: current = 5
        }
        return (current, 5)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: AppTheme.Spacing.small) {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.accent.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Library Backup")
                        .font(AppTheme.Font.bodyBold)
                        .foregroundStyle(.primary)
                    Text("Restore items and collections from a MediaTracker backup")
                        .font(AppTheme.Font.label)
                        .foregroundStyle(.secondary)
                    Text("Step \(stepProgress.current) of \(stepProgress.total)")
                        .font(AppTheme.Font.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if currentStep != .progress {
                    Button(action: {
                        cancelAndDismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                }
            }
            .padding(AppTheme.Spacing.large)

            Divider()

            // Step Content
            VStack {
                switch currentStep {
                case .selectFile:
                    selectFileView
                case .preview:
                    previewView
                case .strategy:
                    strategyView
                case .progress:
                    progressView
                case .summary:
                    summaryView
                }
            }
            .padding(AppTheme.Spacing.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation Bar
            HStack {
                if currentStep == .preview || currentStep == .strategy {
                    Button("Back") {
                        withAnimation(AppTheme.Animation.springSnappy) {
                            if currentStep == .strategy {
                                currentStep = .preview
                            } else if currentStep == .preview {
                                currentStep = .selectFile
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                switch currentStep {
                case .selectFile:
                    Button("Choose File...") {
                        showFileImporter = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.Colors.accent)

                case .preview:
                    Button("Next: Choose Strategy") {
                        withAnimation(AppTheme.Animation.springSnappy) {
                            currentStep = .strategy
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.Colors.accent)

                case .strategy:
                    Button("Start Import") {
                        startImportProcess()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.Colors.accent)

                case .progress:
                    Button("Cancel Import") {
                        cancelImport()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(Color.semanticRed(for: colorScheme))

                case .summary:
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.Colors.accent)
                }
            }
            .padding(AppTheme.Spacing.large)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 480, idealHeight: 540)
        .background(AppTheme.Colors.background(for: colorScheme))
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                analyzeFile(at: url)
            case .failure(let error):
                errorMessage = "Failed to select file: \(error.localizedDescription)"
            }
        }
    }

    // Step 1: Select File
    private var selectFileView: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundStyle(AppTheme.Colors.accent.opacity(0.4))
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                            .fill(AppTheme.Colors.cardFill(for: colorScheme))
                    )

                VStack(spacing: AppTheme.Spacing.medium) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(AppTheme.Colors.accent)

                    VStack(spacing: 4) {
                        Text("Select a MediaTracker Backup")
                            .font(AppTheme.Font.bodyBold)
                            .foregroundStyle(.primary)
                        Text("Supported format: MediaTracker JSON (.json)")
                            .font(AppTheme.Font.label)
                            .foregroundStyle(.secondary)
                    }

                    if isAnalyzing {
                        HStack(spacing: AppTheme.Spacing.small) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Analyzing backup...")
                                .font(AppTheme.Font.label)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(AppTheme.Spacing.xLarge)
            }
            .frame(height: 220)

            if let error = errorMessage {
                HStack(spacing: AppTheme.Spacing.small) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.semanticRed(for: colorScheme))
                    Text(error)
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(Color.semanticRed(for: colorScheme))
                }
            }
        }
    }

    // Step 2: Inspection & Preview
    private var previewView: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            if let backup = backupData {
                GlassCard(color: AppTheme.Colors.accent, isHovered: false) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                        HStack {
                            Label("Backup Inspection", systemImage: "checkmark.seal.fill")
                                .font(AppTheme.Font.bodyBold)
                                .foregroundStyle(AppTheme.Colors.accent)
                            Spacer()
                            Text("Format Version \(backup.version)")
                                .font(AppTheme.Font.caption)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        HStack(spacing: AppTheme.Spacing.large) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Total Items")
                                    .font(AppTheme.Font.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(backup.items.count)")
                                    .font(AppTheme.Font.title2)
                            }

                            Divider().frame(height: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Collections")
                                    .font(AppTheme.Font.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(backup.collections?.count ?? 0)")
                                    .font(AppTheme.Font.title2)
                            }

                            Divider().frame(height: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("New vs Existing")
                                    .font(AppTheme.Font.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(newItemsCount) new · \(existingMatchCount) match")
                                    .font(AppTheme.Font.bodyMedium)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .padding(AppTheme.Spacing.medium)
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Text("Sample Items in Backup:")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(backup.items.prefix(5), id: \.id) { item in
                                HStack {
                                    Image(systemName: item.type == "Movie" ? "film.fill" : "tv.fill")
                                        .foregroundStyle(.secondary)
                                    Text(item.title)
                                        .font(AppTheme.Font.label)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(item.state.capitalized)
                                        .font(AppTheme.Font.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(AppTheme.Colors.cardFill(for: colorScheme))
                                .cornerRadius(6)
                            }
                        }
                    }
                    .frame(height: 120)
                }
            }
        }
    }

    // Step 3: Strategy Selection
    private var strategyView: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("How should existing duplicate titles be handled?")
                .font(AppTheme.Font.bodyBold)
                .foregroundStyle(.primary)

            VStack(spacing: AppTheme.Spacing.small) {
                ForEach(ImportConflictStrategy.allCases) { strategy in
                    Button(action: {
                        selectedStrategy = strategy
                    }) {
                        HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
                            Image(systemName: selectedStrategy == strategy ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(selectedStrategy == strategy ? AnyShapeStyle(AppTheme.Colors.accent) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(strategy.title)
                                    .font(AppTheme.Font.bodyMedium)
                                    .foregroundStyle(.primary)
                                Text(strategy.description)
                                    .font(AppTheme.Font.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(AppTheme.Spacing.medium)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                                .fill(selectedStrategy == strategy ? AppTheme.Colors.accent.opacity(0.1) : AppTheme.Colors.cardFill(for: colorScheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                                .stroke(selectedStrategy == strategy ? AppTheme.Colors.accent.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Step 4: Progress
    private var progressView: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Spacer()

            if let info = progressInfo {
                VStack(spacing: AppTheme.Spacing.medium) {
                    ProgressView(value: Double(info.processedCount), total: Double(max(1, info.totalCount)))
                        .tint(AppTheme.Colors.accent)
                        .controlSize(.large)

                    HStack {
                        Text("Processing \(info.processedCount) of \(info.totalCount) items...")
                            .font(AppTheme.Font.bodyMedium)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(Int((Double(info.processedCount) / Double(max(1, info.totalCount))) * 100))%")
                            .font(AppTheme.Font.bodyBold)
                            .foregroundStyle(AppTheme.Colors.accent)
                    }

                    if !info.currentTitle.isEmpty {
                        Text("Currently importing: \"\(info.currentTitle)\"")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(AppTheme.Spacing.large)
                .background(AppTheme.Colors.cardFill(for: colorScheme))
                .cornerRadius(AppTheme.Radius.medium)
            } else {
                ProgressView("Preparing import...")
            }

            Spacer()
        }
    }

    // Step 5: Summary
    private var summaryView: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(Color.semanticGreen(for: colorScheme))

            Text("Import Completed Successfully!")
                .font(AppTheme.Font.bodyBold)
                .foregroundStyle(.primary)

            if let info = progressInfo {
                HStack(spacing: AppTheme.Spacing.large) {
                    VStack(spacing: 2) {
                        Text("New Added")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.secondary)
                        Text("\(info.importedCount)")
                            .font(AppTheme.Font.title3)
                            .foregroundStyle(Color.semanticGreen(for: colorScheme))
                    }

                    Divider().frame(height: 30)

                    VStack(spacing: 2) {
                        Text("Merged")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.secondary)
                        Text("\(info.mergedCount)")
                            .font(AppTheme.Font.title3)
                            .foregroundStyle(Color.semanticGold(for: colorScheme))
                    }

                    Divider().frame(height: 30)

                    VStack(spacing: 2) {
                        Text("Skipped")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.secondary)
                        Text("\(info.skippedCount)")
                            .font(AppTheme.Font.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(AppTheme.Spacing.large)
                .background(AppTheme.Colors.cardFill(for: colorScheme))
                .cornerRadius(AppTheme.Radius.medium)
            }

            Spacer()
        }
    }

    // File Analysis
    private func analyzeFile(at url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Permission denied to access file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        isAnalyzing = true
        errorMessage = nil

        let container = modelContext.container

        Task.detached(priority: .userInitiated) {
            do {
                let data = try Data(contentsOf: url)
                let backup = try LibraryBackup.createDecoder().decode(LibraryBackup.self, from: data)

                let context = ModelContext(container)
                var descriptor = FetchDescriptor<MediaItem>()
                descriptor.propertiesToFetch = [\.id, \.typeValue]
                let existingItems = (try? context.fetch(descriptor)) ?? []
                let existingKeys = Set(existingItems.map { "\($0.id)_\($0.type?.rawValue ?? "")" })

                var match = 0
                var newCount = 0
                for item in backup.items {
                    let typePrefix = item.type.lowercased().contains("movie") ? "movie" : "tv"
                    let tmdbIDPart = item.id.split(separator: "_").last ?? item.id[...]
                    let key = "\(typePrefix)_\(tmdbIDPart)_\(item.type)"
                    if existingKeys.contains(key) {
                        match += 1
                    } else {
                        newCount += 1
                    }
                }

                await MainActor.run {
                    self.backupData = backup
                    self.existingMatchCount = match
                    self.newItemsCount = newCount
                    self.isAnalyzing = false
                    withAnimation(AppTheme.Animation.springSnappy) {
                        self.currentStep = .preview
                    }
                }
            } catch {
                await MainActor.run {
                    self.isAnalyzing = false
                    self.errorMessage = "Failed to parse backup JSON: \(error.localizedDescription)"
                }
            }
        }
    }

    // Start Import Task
    private func startImportProcess() {
        guard let backup = backupData else { return }

        withAnimation(AppTheme.Animation.springSnappy) {
            currentStep = .progress
        }

        BackgroundTaskManager.shared.isImportActive = true
        BackgroundTaskManager.shared.activeTaskDescription = "Importing \(backup.items.count) library items..."

        let container = modelContext.container
        let strategy = selectedStrategy

        importTask = Task.detached(priority: .userInitiated) {
            let importService = BackgroundDataService(modelContainer: container)

            _ = await importService.importLibraryData(backup: backup, strategy: strategy) { progress in
                Task { @MainActor in
                    self.progressInfo = progress
                }
            }

            await importService.importCollections(backup: backup)

            await MainActor.run {
                BackgroundTaskManager.shared.isImportActive = false
                BackgroundTaskManager.shared.activeTaskDescription = nil
                MediaStateService.shared.postMediaStateChanged()
                
                let context = ModelContext(container)
                DataService.shared.runMaintenance(modelContext: context, silent: true)

                withAnimation(AppTheme.Animation.springSnappy) {
                    self.currentStep = .summary
                }
            }
        }
    }

    private func cancelImport() {
        importTask?.cancel()
        BackgroundTaskManager.shared.isImportActive = false
        BackgroundTaskManager.shared.activeTaskDescription = nil
        dismiss()
    }

    private func cancelAndDismiss() {
        cancelImport()
    }
}
