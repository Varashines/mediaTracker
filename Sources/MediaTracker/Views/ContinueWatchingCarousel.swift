import SwiftData
import SwiftUI

enum ContinueWatchingFilter: String, CaseIterable {
    case all
    case new
    case inProgress

    var title: String {
        switch self {
        case .all: return "All"
        case .new: return "New"
        case .inProgress: return "In Progress"
        }
    }

    var icon: String {
        switch self {
        case .all: return "rectangle.stack.fill"
        case .new: return "sparkles"
        case .inProgress: return "play.circle.fill"
        }
    }
}

struct ContinueWatchingCarousel: View {
    let items: [MediaThumbnailMetadata]
    let namespace: Namespace.ID
    let onSelect: (MediaThumbnailMetadata) -> Void
    var onDiscoverySpotlight: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var filter: ContinueWatchingFilter = .all
    @State private var hoveredPill: ContinueWatchingFilter? = nil
    @Namespace private var cwFilterAnimation

    private static let newRadarBadges: Set<String> = [
        SmartBadge.premiere.rawValue,
        SmartBadge.new.rawValue,
        SmartBadge.bingeDrop.rawValue,
        SmartBadge.soon.rawValue
    ]

    private var filteredItems: [MediaThumbnailMetadata] {
        switch filter {
        case .all:
            return items
        case .new:
            return items.filter { item in
                let badge = item.smartBadgeLabel ?? ""
                let isNewDrop = Self.newRadarBadges.contains(badge)
                let isZeroProgress = (item.progress ?? 0) <= 0.001
                return isNewDrop || isZeroProgress
            }
        case .inProgress:
            return items.filter { item in
                let progress = item.progress ?? 0
                let isUnderway = progress > 0.001
                let isBehindOrBinge = item.smartBadgeLabel == SmartBadge.behind.rawValue ||
                                      item.smartBadgeLabel == SmartBadge.binge.rawValue ||
                                      item.smartBadgeLabel == SmartBadge.hooked.rawValue
                return isUnderway || isBehindOrBinge
            }
        }
    }

    private var filteredEmptyMessage: String {
        switch filter {
        case .all: return "Ready to start watching?"
        case .new: return "No new seasons or upcoming drops right now."
        case .inProgress: return "No titles currently in progress."
        }
    }

    var body: some View {
        let displayItems = filteredItems

        HomeCarouselSection(
            title: "Continue Watching",
            icon: "play.fill",
            iconColor: .blue,
            scrollSpace: "CW_Scroll",
            items: displayItems,
            showsScrollProgress: displayItems.count > 1,
            spacing: AppTheme.Spacing.smallMedium,
            trailingAccessory: items.isEmpty ? nil : { AnyView(filterPills) },
            onSelect: onSelect,
            emptyContent: {
                if items.isEmpty {
                    discoverySpotlightCta
                } else {
                    filterEmptyView
                }
            }
        ) { metadata in
            ContinueWatchingBackdropCard(metadata: metadata)
        }
        .animation(AppTheme.Animation.springSnappy, value: filter)
    }

    private var filterPills: some View {
        HStack(spacing: 2) {
            ForEach(ContinueWatchingFilter.allCases, id: \.self) { option in
                filterPill(option)
            }
        }
        .padding(3)
        .background {
            Capsule().fill(AppTheme.Colors.cardFill(for: colorScheme))
        }
        .overlay {
            Capsule().stroke(
                AppTheme.Colors.strokeDefault(for: colorScheme),
                lineWidth: 0.5
            )
        }
    }

    private func filterPill(_ option: ContinueWatchingFilter) -> some View {
        let isSelected = filter == option
        let isHovered = hoveredPill == option
        return Button {
            withAnimation(AppTheme.Animation.springSnappy) {
                filter = option
            }
            FeedbackManager.shared.trigger(.click)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: option.icon)
                    .font(AppTheme.Font.caption2)
                Text(option.title)
                    .font(AppTheme.Font.caption2)
            }
            .foregroundStyle(isSelected ? AppTheme.Colors.accent.readableForeground : (isHovered ? Color.primary : Color.secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if isSelected {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.Colors.accent, AppTheme.Colors.accent.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .matchedGeometryEffect(id: "activeCWFilterPill", in: cwFilterAnimation)
                        .shadow(color: AppTheme.Colors.accent.opacity(0.35), radius: 4, y: 1)
                }
            }
            .overlay {
                if isSelected {
                    Capsule()
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                        .matchedGeometryEffect(id: "activeCWFilterPillStroke", in: cwFilterAnimation)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.springSnappy) {
                hoveredPill = hovering ? option : nil
            }
        }
    }

    private var filterEmptyView: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: filter.icon)
                .font(AppTheme.Font.title3)
                .foregroundStyle(Color.blue.opacity(0.5))
            Text(filteredEmptyMessage)
                .font(AppTheme.Font.body)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
        .padding(.vertical, AppTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var discoverySpotlightCta: some View {
        Button {
            onDiscoverySpotlight?()
        } label: {
            HStack(spacing: AppTheme.Spacing.medium) {
                Image(systemName: "sparkles.tv.fill")
                    .font(AppTheme.Font.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 54, height: 54)
                    .background(.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))

                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                    Text("Ready to start watching?")
                       .font(AppTheme.Font.title3)
                        .foregroundStyle(.primary)
                    Text("Explore the Discovery Hub to find your next favorite show.")
                        .font(AppTheme.Font.body)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(AppTheme.Spacing.medium)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                    .fill(.thinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
        .padding(.vertical, AppTheme.Spacing.medium - 1)
    }
}
