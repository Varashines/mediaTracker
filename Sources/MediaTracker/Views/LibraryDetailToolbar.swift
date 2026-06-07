import SwiftUI
import SwiftData

struct LibraryDetailToolbarContent: ToolbarContent {
    @Bindable var viewModel: MediaViewModel
    @Binding var sidebarSelection: SidebarItem?
    @Binding var showingBulkManager: Bool
    @Binding var isSyncHovered: Bool
    let isSystemSmartCategory: Bool
    let modelContext: ModelContext
    let onRefresh: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if viewModel.collection.selectedCollectionID != nil {
                collectionNavigationToolbar
            } else if isSystemSmartCategory {
                Button {
                    withAnimation {
                        sidebarSelection = .category(.smartHub)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
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
                    viewModel.collection.selectedCollectionID = nil
                }
                viewModel.filterSubject.send()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
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
            onRefresh()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(isSyncHovered ? 0.1 : 0.06))
                    .frame(width: 32, height: 32)

                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.easeInOut) {
                isSyncHovered = hovering
            }
        }
        .help("Sync Library")
    }
}
