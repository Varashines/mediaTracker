import SwiftUI
import SwiftData

struct LibraryDetailToolbarContent: ToolbarContent {
    @Bindable var viewModel: MediaViewModel
    @Binding var sidebarSelection: SidebarItem?
    @Binding var showingBulkManager: Bool
    @Binding var isSyncHovered: Bool
    let isSystemSmartCategory: Bool
    let isSearchActive: Bool
    let modelContext: ModelContext
    let onRefresh: () -> Void

    private var isSmartCollection: Bool {
        guard let cid = viewModel.collection.selectedCollectionID else { return false }
        let descriptor = FetchDescriptor<MediaCollection>(predicate: #Predicate { $0.id == cid })
        return (try? modelContext.fetch(descriptor).first?.isSmart) ?? false
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if !isSearchActive {
                if viewModel.collection.selectedCollectionID != nil {
                    collectionNavigationToolbar
                } else if isSystemSmartCategory {
                    Button {
                        withAnimation(AppTheme.Animation.springSnappy) {
                            sidebarSelection = .category(.smartHub)
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(AppTheme.Icon.medium)
                    }
                    .help("Back to Smart Hub")
                }
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
                withAnimation(AppTheme.Animation.springSnappy) {
                    sidebarSelection = .category(.smartHub)
                    viewModel.collection.selectedCollectionID = nil
                }
                viewModel.filterSubject.send()
            } label: {
                Image(systemName: "chevron.left")
                    .font(AppTheme.Icon.medium)
            }
            .help("Go Back")

            Button {
                withAnimation(AppTheme.Animation.springSnappy) {
                    viewModel.collection.showingNoteOverlay.toggle()
                }
            } label: {
                let icon = viewModel.collection.showingNoteOverlay ? "bubble.left.and.bubble.right.fill" : "bubble.left.fill"
                let hasNote = !viewModel.collection.currentCollectionNote.isEmpty
                Image(systemName: icon)
                    .font(AppTheme.Icon.medium)
                    .foregroundStyle(hasNote ? AppTheme.Colors.accent : Color.secondary)
            }
            .help("Collection Notes")

            Button {
                showingBulkManager = true
            } label: {
                Image(systemName: "plus.square.on.square")
                    .font(AppTheme.Icon.medium)
            }
            .disabled(isSmartCollection)
            .help(isSmartCollection ? "Cannot manage items in smart collections" : "Manage Items")
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        Button {
            FeedbackManager.shared.trigger(.click)
            onRefresh()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(AppTheme.Icon.medium)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .background(Capsule().fill(.ultraThinMaterial))
        .clipShape(.capsule)
        .frame(width: 32, height: 32)
        .help("Sync Library")
    }
}
