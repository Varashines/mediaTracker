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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        List {
            Spacer().frame(height: AppTheme.Spacing.micro)
            // Primary — always visible, no header collapse
            sidebarRow(
                title: NavigationCategory.home.title, icon: NavigationCategory.home.icon,
                item: .category(.home))
            sidebarRow(
                title: NavigationCategory.discover.title,
                icon: NavigationCategory.discover.icon, item: .category(.discover))
            sidebarRow(
                title: NavigationCategory.upcoming.title,
                icon: NavigationCategory.upcoming.icon, item: .category(.upcoming))

            sectionHeader("LIBRARY")
            sidebarRow(
                title: NavigationCategory.all.title, icon: NavigationCategory.all.icon,
                item: .category(.all))
            sidebarRow(
                title: NavigationCategory.movie.title, icon: NavigationCategory.movie.icon,
                item: .category(.movie))
            sidebarRow(
                title: NavigationCategory.tvShow.title,
                icon: NavigationCategory.tvShow.icon, item: .category(.tvShow))

            sectionHeader("COLLECTIONS")
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

            sectionHeader("ANALYTICS")
            sidebarRow(
                title: NavigationCategory.insights.title,
                icon: NavigationCategory.insights.icon, item: .category(.insights))
            sidebarRow(
                title: "Year in Review",
                icon: "calendar.badge.sparkles", item: .yearReview)

            Spacer().frame(height: AppTheme.Spacing.tiny)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.Font.smallBold)
            .kerning(AppTheme.Kerning.wide)
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppTheme.Spacing.small)
            .padding(.top, AppTheme.Spacing.tiny)
            .padding(.bottom, AppTheme.Spacing.micro)
            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
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
            withAnimation(AppTheme.Animation.springSnappy) {
                selection = item
            }
            FeedbackManager.shared.trigger(.click)
        } label: {
            HStack(spacing: AppTheme.Spacing.small) {
                CollectionIconView(systemImage: iconName, font: AppTheme.Icon.medium, color: isSelected ? .white : (isHovered ? .primary : .secondary))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: AppTheme.Spacing.large)
                    .scaleEffect(isSelected ? 1.1 : 1.0)

                Text(title)
                    .font(AppTheme.Font.body.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : (isHovered ? .primary : Color.secondary))

                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.small)
            .padding(.vertical, AppTheme.Spacing.tiny)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                        .fill(AppTheme.Colors.accent)
                        .shadow(color: AppTheme.Colors.accent.opacity(0.25), radius: 6, y: 2)
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        }
                        .matchedGeometryEffect(id: "sidebar_selection", in: sidebarNamespace)
                } else {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                        .fill(isHovered ? AppTheme.Colors.surfaceSubtle(for: scheme) : .clear)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(AppTheme.Animation.springSnappy, value: isSelected)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.microInteraction) {
                hoveredItem = hovering ? item : nil
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}


