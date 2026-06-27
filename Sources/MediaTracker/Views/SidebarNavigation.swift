import SwiftData
import SwiftUI

@MainActor
struct SidebarNavigation: View {
    @Binding var selection: SidebarItem?
    @Query(filter: #Predicate<MediaCollection> { $0.isPinned }) private var pinnedCollections:
        [MediaCollection]
    @AppStorage("pinned_system_categories") private var pinnedSystemCategories: String = "Release Radar"
    @State private var hoveredItem: SidebarItem? = nil
    @Namespace private var sidebarNamespace

    var body: some View {
        List {
            Section {
                sidebarRow(
                    title: NavigationCategory.home.title, icon: NavigationCategory.home.icon,
                    item: .category(.home))
                sidebarRow(
                    title: NavigationCategory.discover.title,
                    icon: NavigationCategory.discover.icon, item: .category(.discover))
                sidebarRow(
                    title: NavigationCategory.upcoming.title,
                    icon: NavigationCategory.upcoming.icon, item: .category(.upcoming))
            } header: {
                Spacer().frame(height: 1)
            }

            Section {
                sidebarRow(
                    title: NavigationCategory.all.title, icon: NavigationCategory.all.icon,
                    item: .category(.all))
                sidebarRow(
                    title: NavigationCategory.movie.title, icon: NavigationCategory.movie.icon,
                    item: .category(.movie))
                sidebarRow(
                    title: NavigationCategory.tvShow.title,
                    icon: NavigationCategory.tvShow.icon, item: .category(.tvShow))
            } header: {
                Text("LIBRARY")
                    .font(AppTheme.Font.smallBold)
                    .kerning(1.2)
                    .foregroundStyle(.secondary.opacity(0.7))
            }

            Section {
                sidebarRow(
                    title: NavigationCategory.smartHub.title,
                    icon: NavigationCategory.smartHub.icon, item: .category(.smartHub))

                let pinnedSystemList = pinnedSystemCategories.split(separator: ",")
                    .map(String.init)
                    .compactMap { NavigationCategory(rawValue: $0) }

                ForEach(pinnedSystemList) { category in
                    sidebarRow(
                        title: category.title,
                        icon: category.icon,
                        item: .category(category))
                }

                ForEach(pinnedCollections) { collection in
                    sidebarRow(
                        title: collection.name, icon: collection.systemImage,
                        item: .collection(
                            collection.id, name: collection.name, icon: collection.systemImage))
                }
            } header: {
                Text("COLLECTIONS")
                    .font(AppTheme.Font.smallBold)
                    .kerning(1.2)
                    .foregroundStyle(.secondary.opacity(0.7))
            }

            Section {
                sidebarRow(
                    title: NavigationCategory.insights.title,
                    icon: NavigationCategory.insights.icon, item: .category(.insights))
            } header: {
                Text("ANALYTICS")
                    .font(AppTheme.Font.smallBold)
                    .kerning(1.2)
                    .foregroundStyle(.secondary.opacity(0.7))
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarRow(title: String, icon: String, item: SidebarItem) -> some View {
        let isSelected = selection == item
        let isHovered = hoveredItem == item

        let iconName: String
        if isSelected && !icon.isEmoji {
            if icon.contains(".fill") || icon == "calendar" || icon == "cpu" || icon == "sparkles" || icon == "calendar.badge.clock" || icon == "calendar.badge.sparkles" || icon == "sparkles.tv" || icon == "sparkles.rectangle.stack" {
                iconName = icon
            } else {
                iconName = "\(icon).fill"
            }
        } else {
            iconName = icon
        }

        return Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                selection = item
            }
            FeedbackManager.shared.trigger(.click)
        } label: {
            HStack(spacing: AppTheme.Spacing.small) {
                CollectionIconView(systemImage: iconName, font: AppTheme.Icon.medium, color: isSelected ? .white : Color.primary.opacity(0.6))
                    .frame(width: AppTheme.Spacing.large)
                    .scaleEffect(isSelected ? 1.1 : 1.0)

                Text(title)
                    .font(AppTheme.Font.body.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : Color.secondary)

                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.small)
            .padding(.vertical, AppTheme.Spacing.tiny)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                        .fill(AppTheme.Colors.accent)
                        .matchedGeometryEffect(id: "sidebar_selection", in: sidebarNamespace)
                } else {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.04) : .clear)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.45, dampingFraction: 0.65), value: isSelected)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.microInteraction) {
                hoveredItem = hovering ? item : nil
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}


