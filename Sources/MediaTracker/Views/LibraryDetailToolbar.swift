import SwiftUI
import SwiftData

struct LibraryDetailToolbarContent: ToolbarContent {
    @Bindable var viewModel: MediaViewModel
    @Binding var sidebarSelection: SidebarItem?
    @Binding var showingBulkManager: Bool
    let isSystemSmartCategory: Bool
    let isSearchActive: Bool
    let modelContext: ModelContext
    let onRefresh: () -> Void

    @State private var showViewOptions = false
    @State private var refreshRotation: Double = 0
    @Environment(\.colorScheme) private var colorScheme

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
                    viewOptionsButton
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
    private var viewOptionsButton: some View {
        if isLibraryCategory {
            let hasCustomView = viewModel.filter.currentSortOrder != .recentlyAdded
                || viewModel.filter.currentGroupBy != .none

            Button {
                showViewOptions.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(AppTheme.Icon.medium)
                .overlay(alignment: .topTrailing) {
                    if hasCustomView {
                        Circle()
                            .fill(AppTheme.Colors.accent)
                            .frame(width: 6, height: 6)
                            .offset(x: 6, y: -4)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(hasCustomView ? AppTheme.Colors.accent.opacity(0.12) : AppTheme.Colors.surfaceGhost(for: colorScheme))
                )
            }
            .buttonStyle(.borderless)
            .contentShape(Capsule())
            .tint(.primary)
            .help("View options")
            .accessibilityLabel("Library view options")
            .accessibilityValue("Sorted by \(viewModel.filter.currentSortOrder.rawValue), grouped by \(viewModel.filter.currentGroupBy.rawValue)")
            .popover(isPresented: $showViewOptions) {
                ViewOptionsPopover(
                    sortOrder: viewModel.filter.currentSortOrder,
                    groupBy: viewModel.filter.currentGroupBy,
                    onSelectSort: { newOrder in
                    viewModel.filter.categorySortOrders[viewModel.filter.selectedCategory] = newOrder
                    viewModel.filterSubject.send()
                    },
                    onSelectGroup: { newGroup in
                    viewModel.filter.categoryGroupBys[viewModel.filter.selectedCategory] = newGroup
                    viewModel.filterSubject.send()
                    }
                )
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
            .accessibilityLabel("Back to collections")

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
                .padding(5)
                .background(
                    Circle()
                        .fill(AppTheme.Colors.surfaceGhost(for: colorScheme))
                )
        }
        .buttonStyle(.borderless)
        .contentShape(Circle())
        .tint(.primary)
        .help("Sync Library")
        .accessibilityLabel("Sync Library")
    }
}

// MARK: - View Options Popover

private struct ViewOptionsPopover: View {
    let sortOrder: SortOrder
    let groupBy: GroupBy
    let onSelectSort: (SortOrder) -> Void
    let onSelectGroup: (GroupBy) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            optionSection(title: "Sort by", icon: "arrow.up.arrow.down") {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    optionButton(
                        icon: order.icon,
                        label: order.rawValue,
                        isSelected: order == sortOrder
                    ) {
                        onSelectSort(order)
                    }
                }
            }

            Divider()

            optionSection(title: "Group by", icon: "square.grid.2x2") {
                ForEach(GroupBy.pickerOptions, id: \.self) { group in
                    optionButton(
                        icon: group.icon,
                        label: group.rawValue,
                        isSelected: group == groupBy
                    ) {
                        onSelectGroup(group)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.small)
        .frame(width: 230)
    }

    private func optionSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
            Label(title, systemImage: icon)
                .font(AppTheme.Font.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppTheme.Spacing.micro)

            content()
        }
    }

    private func optionButton(
        icon: String,
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: icon)
                    .font(AppTheme.Icon.medium)
                    .frame(width: 18)
                Text(label)
                    .font(AppTheme.Font.body)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(AppTheme.Colors.accent)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.small)
            .padding(.vertical, AppTheme.Spacing.mini)
            .background(
                isSelected ? AppTheme.Colors.accent.opacity(0.10) : .clear,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Shared Option Row

private struct PickerOptionRow: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let isHovered: Bool
    @Environment(\.colorScheme) private var colorScheme

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
                .fill(isHovered ? AppTheme.Colors.surfaceSubtle(for: colorScheme) : .clear)
        )
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? AppTheme.Colors.surfaceGhost(for: colorScheme) : .clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}
