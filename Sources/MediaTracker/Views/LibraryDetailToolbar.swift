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

    @State private var showSortPicker = false
    @State private var showGroupPicker = false
    @State private var refreshRotation: Double = 0

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
                    .tint(.primary)
                    .help("Back to Smart Hub")
                }
            }
        }

        ToolbarItem(placement: .primaryAction) {
            if !isSearchActive {
                HStack(spacing: AppTheme.Spacing.tiny) {
                    sortMenu
                    groupMenu
                    refreshButton
                }
            }
        }
    }

    private var isLibraryCategory: Bool {
        switch viewModel.filter.selectedCategory {
        case .all, .movie, .tvShow, .completed: return true
        default: return false
        }
    }

    @ViewBuilder
    private var sortMenu: some View {
        if isLibraryCategory {
            Button {
                showSortPicker.toggle()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: viewModel.filter.currentSortOrder.icon)
                        .font(AppTheme.Icon.medium)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            .help(viewModel.filter.currentSortOrder.rawValue)
            .popover(isPresented: $showSortPicker) {
                SortPickerPopover(
                    current: viewModel.filter.currentSortOrder
                ) { newOrder in
                    viewModel.filter.categorySortOrders[viewModel.filter.selectedCategory] = newOrder
                    viewModel.filterSubject.send()
                    showSortPicker = false
                }
            }
        }
    }

    @ViewBuilder
    private var groupMenu: some View {
        if isLibraryCategory {
            Button {
                showGroupPicker.toggle()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: viewModel.filter.currentGroupBy.icon)
                        .font(AppTheme.Icon.medium)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .overlay(alignment: .topTrailing) {
                    if viewModel.filter.currentGroupBy != .none {
                        Circle()
                            .fill(Color.primary.opacity(0.4))
                            .frame(width: 5, height: 5)
                            .offset(x: 6, y: -4)
                    }
                }
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            .help(viewModel.filter.currentGroupBy != .none ? "Group: \(viewModel.filter.currentGroupBy.rawValue)" : "Group")
            .popover(isPresented: $showGroupPicker) {
                GroupPickerPopover(
                    current: viewModel.filter.currentGroupBy
                ) { newGroup in
                    viewModel.filter.categoryGroupBys[viewModel.filter.selectedCategory] = newGroup
                    viewModel.filterSubject.send()
                    showGroupPicker = false
                }
            }
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
            .tint(.primary)
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
                    .foregroundStyle(hasNote ? .secondary : Color.secondary)
            }
            .tint(.primary)
            .help("Collection Notes")

            Button {
                showingBulkManager = true
            } label: {
                Image(systemName: "plus.square.on.square")
                    .font(AppTheme.Icon.medium)
            }
            .tint(.primary)
            .disabled(isSmartCollection)
            .help(isSmartCollection ? "Cannot manage items in smart collections" : "Manage Items")
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        Button {
            FeedbackManager.shared.trigger(.click)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                refreshRotation += 360
            }
            onRefresh()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(AppTheme.Icon.medium)
                .rotationEffect(.degrees(refreshRotation))
        }
        .buttonStyle(.borderless)
        .tint(.primary)
        .help("Sync Library")
    }
}

// MARK: - Sort Picker Popover

private struct SortPickerPopover: View {
    let current: SortOrder
    let onSelect: (SortOrder) -> Void
    @State private var hoveredOption: SortOrder? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10))
                Text("Sort By")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.top, 16)
            .padding(.bottom, 10)
            .padding(.horizontal, 14)

            VStack(spacing: 2) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    PickerOptionRow(
                        icon: order.icon,
                        label: order.rawValue,
                        isSelected: order == current,
                        isHovered: hoveredOption == order
                    )
                    .onTapGesture { onSelect(order) }
                    .onHover { hovering in
                        hoveredOption = hovering ? order : nil
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .frame(width: 210)
    }
}

// MARK: - Group Picker Popover

private struct GroupPickerPopover: View {
    let current: GroupBy
    let onSelect: (GroupBy) -> Void
    @State private var hoveredOption: GroupBy? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 10))
                Text("Group By")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.top, 16)
            .padding(.bottom, 10)
            .padding(.horizontal, 14)

            VStack(spacing: 2) {
                ForEach(GroupBy.allCases, id: \.self) { group in
                    PickerOptionRow(
                        icon: group.icon,
                        label: group.rawValue,
                        isSelected: group == current,
                        isHovered: hoveredOption == group
                    )
                    .onTapGesture { onSelect(group) }
                    .onHover { hovering in
                        hoveredOption = hovering ? group : nil
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .frame(width: 220)
    }
}

// MARK: - Shared Option Row

private struct PickerOptionRow: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 20)
            Text(label)
                .font(.system(size: 12))
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
        )
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.primary.opacity(0.04) : .clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}
