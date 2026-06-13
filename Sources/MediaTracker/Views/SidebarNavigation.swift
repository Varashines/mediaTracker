import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

@MainActor
struct SidebarNavigation: View {
    @Binding var selection: SidebarItem?
    @Query(filter: #Predicate<MediaCollection> { $0.isPinned }) private var pinnedCollections:
        [MediaCollection]
    @AppStorage("pinned_system_categories") private var pinnedSystemCategories: String = "Release Radar"
    @Environment(\.colorScheme) var colorScheme
    @State private var hoveredItem: SidebarItem? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                // Main Section
                VStack(alignment: .leading, spacing: 4) {
                    sidebarRow(
                        title: NavigationCategory.home.title, icon: NavigationCategory.home.icon,
                        item: .category(.home))
                    sidebarRow(
                        title: NavigationCategory.discover.title,
                        icon: NavigationCategory.discover.icon, item: .category(.discover))
                    sidebarRow(
                        title: NavigationCategory.upcoming.title,
                        icon: NavigationCategory.upcoming.icon, item: .category(.upcoming))
                }
                .padding(.bottom, 16)

                sidebarSectionHeader("LIBRARY")
                VStack(alignment: .leading, spacing: 4) {
                    sidebarRow(
                        title: NavigationCategory.all.title, icon: NavigationCategory.all.icon,
                        item: .category(.all))
                    sidebarRow(
                        title: NavigationCategory.movie.title, icon: NavigationCategory.movie.icon,
                        item: .category(.movie))
                    sidebarRow(
                        title: NavigationCategory.tvShow.title,
                        icon: NavigationCategory.tvShow.icon, item: .category(.tvShow))
                }
                .padding(.bottom, 16)

                sidebarSectionHeader("COLLECTIONS")
                VStack(alignment: .leading, spacing: 4) {
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
                }
                .padding(.bottom, 16)

                sidebarSectionHeader("ANALYTICS")
                sidebarRow(
                    title: NavigationCategory.insights.title,
                    icon: NavigationCategory.insights.icon, item: .category(.insights))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 16)
        }
        .background(SidebarVisualEffectView())
    }

    private func sidebarRow(title: String, icon: String, item: SidebarItem) -> some View {
        let isSelected = selection == item
        
        let activeColor = AppTheme.Colors.accent

        // Only append .fill if the icon name doesn't already contain it and it's a standard symbol
        let iconName: String
        if isSelected {
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
                Image(systemName: iconName)
                    .font(AppTheme.Icon.medium)
                    .foregroundStyle(isSelected ? .white : Color.primary.opacity(0.6))
                    .frame(width: AppTheme.Spacing.large)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : Color.secondary)

                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.small)
            .padding(.vertical, AppTheme.Spacing.tiny)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(isSelected ? activeColor : (hoveredItem == item ? Color.primary.opacity(0.04) : .clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .onHover { isHovered in
            withAnimation(AppTheme.Animation.easeInOut) {
                hoveredItem = isHovered ? item : nil
            }
        }
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.Font.smallBold)
            .kerning(1.2)
            .foregroundStyle(.secondary.opacity(0.7))
            .padding(.leading, AppTheme.Spacing.small)
            .padding(.bottom, AppTheme.Spacing.micro)
    }
}

#if os(macOS)
struct SidebarVisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
#endif


