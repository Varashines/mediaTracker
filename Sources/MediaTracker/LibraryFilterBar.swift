import SwiftUI
import SwiftData

struct LibraryFilterBar: View {
    @Bindable var viewModel: MediaViewModel
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var filterNamespace
    
    // Year options: Current year down to 1950
    private let years: [String] = {
        let currentYear = Calendar.current.component(.year, from: Date())
        return (1950...currentYear).map { String($0) }.reversed()
    }()
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.small) {
                // 1. GENRE FILTER
                filterMenu(
                    title: viewModel.selectedGenre ?? "All Genres",
                    icon: "tag.fill",
                    active: viewModel.selectedGenre != nil
                ) {
                    Button("All Genres") { updateGenre(nil) }
                    Divider()
                    ForEach(viewModel.cachedGenres.map { $0.name }.sorted(), id: \.self) { genre in
                        Button(genre) { updateGenre(genre) }
                    }
                }
                
                // 2. STATUS FILTER
                filterMenu(
                    title: viewModel.selectedState?.displayName ?? "All Status",
                    icon: "clock.fill",
                    active: viewModel.selectedState != nil
                ) {
                    Button("All Status") { updateState(nil) }
                    Divider()
                    ForEach(MediaState.allCases, id: \.self) { state in
                        Button(action: { updateState(state) }) {
                            Label(state.displayName, systemImage: state.iconName)
                        }
                    }
                }
                
                // 3. YEAR FILTER
                filterMenu(
                    title: viewModel.selectedYear ?? "All Years",
                    icon: "calendar",
                    active: viewModel.selectedYear != nil
                ) {
                    Button("All Years") { updateYear(nil) }
                    Divider()
                    ForEach(years, id: \.self) { year in
                        Button(year) { updateYear(year) }
                    }
                }

                Rectangle()
                    .fill(.secondary.opacity(0.2))
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, AppTheme.Spacing.micro)

                // 4. SORT BY
                sortMenu
                
                // 5. GROUP BY
                groupMenu
            }
            .padding(.horizontal, AppTheme.Spacing.section)
            .padding(.vertical, AppTheme.Spacing.tiny)
        }
    }
    
    @ViewBuilder
    private func filterMenu<Content: View>(
        title: String,
        icon: String,
        active: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(AppTheme.Font.caption)
                Text(title)
                    .font(AppTheme.Font.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(active ? AppTheme.Colors.accent : .primary.opacity(0.7))
            .background {
                ZStack {
                    Capsule()
                        .fill(.regularMaterial)
                    
                    if active {
                        Capsule()
                            .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.15 : 0.12))
                            .matchedGeometryEffect(id: "filter_active", in: filterNamespace)
                    }
                }
            }
            .overlay {
                Capsule()
                    .stroke(active ? AppTheme.Colors.accent.opacity(0.2) : .primary.opacity(0.05), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var sortMenu: some View {
        let currentSort = viewModel.currentSortOrder
        return filterMenu(
            title: currentSort.rawValue,
            icon: "arrow.up.arrow.down",
            active: false // Keep sort neutral as it's always active
        ) {
            Picker("Sort By", selection: Binding(
                get: { currentSort },
                set: {
                    viewModel.categorySortOrders[viewModel.selectedCategory] = $0
                    viewModel.filterSubject.send()
                }
            )) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Label(order.rawValue, systemImage: order.icon).tag(order)
                }
            }
        }
    }

    private var groupMenu: some View {
        let currentGroup = viewModel.currentGroupBy
        let isActive = currentGroup != .none
        
        return filterMenu(
            title: isActive ? "By \(currentGroup.rawValue)" : "Group",
            icon: currentGroup.icon,
            active: isActive
        ) {
            Picker("Group By", selection: Binding(
                get: { currentGroup },
                set: {
                    viewModel.categoryGroupBys[viewModel.selectedCategory] = $0
                    viewModel.filterSubject.send()
                }
            )) {
                ForEach(GroupBy.allCases, id: \.self) { group in
                    Label(group.rawValue, systemImage: group.icon).tag(group)
                }
            }
        }
    }
    
    private func updateGenre(_ genre: String?) {
        withAnimation {
            viewModel.selectedGenre = genre
            viewModel.filterSubject.send()
        }
    }
    
    private func updateState(_ state: MediaState?) {
        withAnimation {
            viewModel.selectedState = state
            viewModel.filterSubject.send()
        }
    }
    
    private func updateYear(_ year: String?) {
        withAnimation {
            viewModel.selectedYear = year
            viewModel.filterSubject.send()
        }
    }
}
