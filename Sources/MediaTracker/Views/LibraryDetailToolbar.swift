import SwiftUI
import SwiftData

struct LibraryDetailToolbarContent: ToolbarContent {
    @Bindable var viewModel: MediaViewModel
    @Binding var sidebarSelection: SidebarItem?
    @Binding var showingBulkManager: Bool
    let isSystemSmartCategory: Bool
    let isSearchActive: Bool
    let onRefresh: () -> Void

    @State private var showViewOptions = false
    @State private var showFilters = false
    @State private var refreshRotation: Double = 0
    @Environment(\.colorScheme) private var colorScheme

    /// Cached on CollectionState at selection time — never fetches per render.
    private var isSmartCollection: Bool { viewModel.collection.isSmartCollection }

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
                    if isLibraryCategory {
                        filterButton
                    }
                    viewOptionsButton
                    if canRefreshCurrentCategory {
                        refreshButton
                    }
                }
            }
        }
    }

    private var canRefreshCurrentCategory: Bool {
        switch viewModel.filter.selectedCategory {
        case .discover, .upcoming, .insights:
            return true
        case .smartHub:
            return viewModel.collection.selectedCollectionID == nil
        default:
            return false
        }
    }

    private var isLibraryCategory: Bool {
        switch viewModel.filter.selectedCategory {
        case .all, .movie, .tvShow, .completed: return true
        default: return false
        }
    }

    private var activeFilterCount: Int {
        [
            !viewModel.filter.selectedNetworks.isEmpty,
            !viewModel.filter.selectedLanguages.isEmpty,
            !viewModel.filter.selectedGenres.isEmpty,
            !viewModel.filter.selectedYears.isEmpty,
            !viewModel.filter.selectedStates.isEmpty,
            !viewModel.filter.selectedProviders.isEmpty
        ].filter { $0 }.count
    }

    private var filterButton: some View {
        Button {
            showFilters.toggle()
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(AppTheme.Icon.medium)
                .overlay(alignment: .topTrailing) {
                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Circle().fill(AppTheme.Colors.accent))
                            .offset(x: 9, y: -7)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(activeFilterCount > 0 ? AppTheme.Colors.accent.opacity(0.12) : AppTheme.Colors.surfaceGhost(for: colorScheme))
                )
        }
        .buttonStyle(.borderless)
        .contentShape(Capsule())
        .tint(.primary)
        .help("Library filters")
        .accessibilityLabel("Library filters")
        .accessibilityValue(activeFilterCount == 0 ? "No filters" : "\(activeFilterCount) active")
        .popover(isPresented: $showFilters) {
            LibraryFilterPopover(viewModel: viewModel) {
                viewModel.filterSubject.send()
            }
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
        let isSmartCollectionState = isSmartCollection
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
            .disabled(isSmartCollectionState)
            .help(isSmartCollectionState ? "Cannot manage items in smart collections" : "Manage Items")
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        Button {
            FeedbackManager.shared.trigger(.click)
            AppTheme.Animation.with(AppTheme.Animation.toolbarPop) {
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
        .help(refreshTooltip)
        .accessibilityLabel(refreshTooltip)
    }

    private var refreshTooltip: String {
        switch viewModel.filter.selectedCategory {
        case .discover: return "Refresh Discovery"
        case .upcoming: return "Refresh Calendar"
        case .insights: return "Refresh Insights"
        case .smartHub: return "Refresh Collections"
        default: return "Refresh"
        }
    }
}

private struct LibraryFilterPopover: View {
    @Bindable var viewModel: MediaViewModel
    let onChanged: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var availableYears: [String] = []
    @State private var isLoadingYears = false

    private func binding<Value: Hashable>(for keyPath: WritableKeyPath<FilterState, [Value]>) -> Binding<Set<Value>> {
        Binding(
            get: { Set(viewModel.filter[keyPath: keyPath]) },
            set: { viewModel.filter[keyPath: keyPath] = Array($0) }
        )
    }

    private var hasActiveFilters: Bool {
        !viewModel.filter.selectedNetworks.isEmpty
            || !viewModel.filter.selectedLanguages.isEmpty
            || !viewModel.filter.selectedGenres.isEmpty
            || !viewModel.filter.selectedYears.isEmpty
            || !viewModel.filter.selectedStates.isEmpty
            || !viewModel.filter.selectedProviders.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack {
                Label("Filters", systemImage: "line.3.horizontal.decrease")
                    .font(.headline)
                Spacer()
                Button("Clear All") {
                    viewModel.filter.resetFilters()
                    onChanged()
                }
                .disabled(!hasActiveFilters)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    LibraryMultiSelectMenu(
                        title: "Networks",
                        options: viewModel.discovery.cachedNetworks.map(\.name),
                        selection: binding(for: \.selectedNetworks),
                        onChanged: onChanged
                    )

                    LibraryMultiSelectMenu(
                        title: "Languages",
                        options: viewModel.discovery.cachedLanguages.map { $0.code ?? $0.name },
                        label: { code in
                            viewModel.discovery.cachedLanguages.first { ($0.code ?? $0.name) == code }?.name ?? code
                        },
                        selection: binding(for: \.selectedLanguages),
                        onChanged: onChanged
                    )

                    LibraryMultiSelectMenu(
                        title: "Genres",
                        options: viewModel.discovery.cachedGenres.map(\.name),
                        selection: binding(for: \.selectedGenres),
                        onChanged: onChanged
                    )

                    LibraryMultiSelectMenu(
                        title: "Years",
                        options: availableYears,
                        selection: binding(for: \.selectedYears),
                        onChanged: onChanged,
                        isDisabled: isLoadingYears
                    )

                    LibraryMultiSelectMenu(
                        title: "Statuses",
                        options: MediaState.allCases,
                        label: \.displayName,
                        selection: binding(for: \.selectedStates),
                        onChanged: onChanged
                    )

                    LibraryMultiSelectMenu(
                        title: "Providers",
                        options: viewModel.discovery.cachedProviders.map(\.name),
                        selection: binding(for: \.selectedProviders),
                        onChanged: onChanged
                    )
                }
            }
            .frame(maxHeight: 360)
        }
        .padding(AppTheme.Spacing.large)
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
        .task {
            guard availableYears.isEmpty, !isLoadingYears else { return }
            isLoadingYears = true
            let actor = MediaFilterActor.shared(modelContainer: modelContext.container)
            availableYears = await actor.fetchDistinctYears()
            isLoadingYears = false
        }
    }

}

private struct LibraryMultiSelectMenu<Value: Hashable>: View {
    let title: String
    let options: [Value]
    var label: (Value) -> String = { String(describing: $0) }
    @Binding var selection: Set<Value>
    let onChanged: () -> Void
    var isDisabled = false

    private var summary: String {
        if selection.isEmpty { return "All \(title.lowercased())" }
        if selection.count == 1, let value = selection.first { return label(value) }
        return "\(selection.count) \(title.lowercased())"
    }

    var body: some View {
        Menu {
            Button("Clear \(title)") {
                selection.removeAll()
                onChanged()
            }
            ForEach(options, id: \.self) { option in
                Button {
                    if selection.contains(option) {
                        selection.remove(option)
                    } else {
                        selection.insert(option)
                    }
                    onChanged()
                } label: {
                    if selection.contains(option) {
                        Label(label(option), systemImage: "checkmark")
                    } else {
                        Text(label(option))
                    }
                }
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.small) {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .disabled(isDisabled)
        .accessibilityLabel(title)
        .accessibilityValue(summary)
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
