import SwiftUI
import SwiftData

struct LibraryDetailToolbarContent: ToolbarContent {
    @Bindable var viewModel: MediaViewModel
    @Binding var sidebarSelection: SidebarItem?
    @Binding var showingBulkManager: Bool
    @Binding var isSyncHovered: Bool
    let isSystemSmartCategory: Bool
    let modelContext: ModelContext

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if viewModel.selectedCollectionID != nil {
                collectionNavigationToolbar
            } else if isSystemSmartCategory {
                Button {
                    withAnimation {
                        sidebarSelection = .category(.smartHub)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(AppTheme.Font.heading)
                }
                .help("Back to Smart Hub")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            refreshButton
        }
    }

    @ViewBuilder
    private var collectionNavigationToolbar: some View {
        HStack(spacing: AppTheme.Spacing.micro) {
            Button {
                withAnimation {
                    sidebarSelection = .category(.smartHub)
                    viewModel.selectedCollectionID = nil
                }
                viewModel.filterSubject.send()
            } label: {
                Image(systemName: "chevron.left")
                    .font(AppTheme.Font.heading)
            }
            .help("Go Back")

            Button {
                withAnimation(AppTheme.Animation.springSnappy) {
                    viewModel.showingNoteOverlay.toggle()
                }
            } label: {
                let icon = viewModel.showingNoteOverlay ? "bubble.left.and.bubble.right.fill" : "bubble.left.fill"
                let hasNote = !viewModel.currentCollectionNote.isEmpty
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(hasNote ? Color.blue : Color.secondary)
            }
            .help("Collection Notes")

            Button {
                showingBulkManager = true
            } label: {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 14))
            }
            .help("Manage Items")
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        Button {
            if viewModel.selectedCategory == .discover {
                ImageCache.shared.clearFullCache()
                viewModel.discoveryRefreshTrigger += 1
            } else {
                performLibrarySync()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(isSyncHovered ? 0.1 : 0.06))
                    .frame(width: 32, height: 32)

                if DataService.shared.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(AppTheme.Font.heading)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.easeInOut) {
                isSyncHovered = hovering
            }
        }
        .help("Sync Library")
        .disabled(DataService.shared.isRefreshing)
    }

    private func performLibrarySync() {
        guard !DataService.shared.isRefreshing else { return }

        let container = modelContext.container
        Task {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<MediaItem>()
            guard let items = try? context.fetch(descriptor) else { return }
            let ids = items.map(\.id)
            await MainActor.run {
                DataService.shared.refreshMetadata(forIDs: ids, modelContext: modelContext, force: true)
            }
        }
    }
}
