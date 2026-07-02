import SwiftUI
import SwiftData

struct StudiosNetworksView: View {
    let stats: LibraryStats
    let modelContext: ModelContext

    @State private var logoMap: [String: String] = [:]
    @State private var colorMap: [String: String] = [:]
    @State private var aliasMap: [String: String] = [:]
    @State private var cachedStudioItems: [(String, Double, String?, String?)] = []
    @State private var cachedNetworkItems: [(String, Double, String?, String?)] = []

    private func computeGroupedItems() {
        cachedStudioItems = Self.groupedItems(stats.topRatedStudios, aliasMap: aliasMap, logoMap: logoMap, colorMap: colorMap)
        cachedNetworkItems = Self.groupedItems(stats.topRatedNetworks, aliasMap: aliasMap, logoMap: logoMap, colorMap: colorMap)
    }

    private static func groupedItems(_ items: [(name: String, score: Double)], aliasMap: [String: String], logoMap: [String: String], colorMap: [String: String]) -> [(String, Double, String?, String?)] {
        var grouped: [String: (score: Double, logoPath: String?, themeColorHex: String?)] = [:]
        for (name, score) in items {
            let target = aliasMap[name] ?? name
            if let existing = grouped[target] {
                grouped[target] = (
                    score: existing.score + score,
                    logoPath: existing.logoPath ?? logoMap[target] ?? logoMap[name],
                    themeColorHex: existing.themeColorHex ?? colorMap[target] ?? colorMap[name]
                )
            } else {
                grouped[target] = (
                    score: score,
                    logoPath: logoMap[target] ?? logoMap[name],
                    themeColorHex: colorMap[target] ?? colorMap[name]
                )
            }
        }
        return grouped
            .map { ($0.key, $0.value.score, $0.value.logoPath, $0.value.themeColorHex) }
            .sorted { $0.1 > $1.1 }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            // Studios
            let studioItems = cachedStudioItems
            if !studioItems.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    SectionHeader(title: "Studios", icon: "building.2.fill", iconColor: AppTheme.Colors.accent)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: AppTheme.Spacing.large) {
                            ForEach(Array(studioItems.enumerated()), id: \.0) { idx, item in
                                RankedCard(
                                    rank: idx + 1,
                                    name: item.0,
                                    score: item.1,
                                    logoPath: item.2,
                                    themeColor: .orange
                                )
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        .padding(.vertical, 4)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }

            // Networks
            let networkItems = cachedNetworkItems
            if !networkItems.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    SectionHeader(title: "Networks", icon: "antenna.radiowaves.left.and.right", iconColor: AppTheme.Colors.accent)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: AppTheme.Spacing.large) {
                            ForEach(Array(networkItems.enumerated()), id: \.0) { idx, item in
                                RankedCard(
                                    rank: idx + 1,
                                    name: item.0,
                                    score: item.1,
                                    logoPath: item.2,
                                    themeColor: .teal
                                )
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        .padding(.vertical, 4)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }

            // Languages
            if !stats.topRatedLanguages.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    SectionHeader(title: "Languages", icon: "globe", iconColor: AppTheme.Colors.accent)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: AppTheme.Spacing.large)], spacing: AppTheme.Spacing.large) {
                        ForEach(Array(stats.topRatedLanguages.prefix(6).enumerated()), id: \.element.name) { idx, item in
                            RankedCard(
                                rank: idx + 1,
                                name: item.name,
                                score: item.1,
                                logoPath: nil,
                                themeColor: .purple
                            )
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }
            }
        }
        .task {
            let netDescriptor = FetchDescriptor<NetworkEntity>()
            if let networks = try? modelContext.fetch(netDescriptor) {
                for net in networks {
                    if let path = net.logoPath { logoMap[net.name] = path }
                    if let hex = net.themeColorHex { colorMap[net.name] = hex }
                }
            }
            let aliasDescriptor = FetchDescriptor<StudioAliasEntity>()
            if let aliases = try? modelContext.fetch(aliasDescriptor) {
                var map: [String: String] = [:]
                for alias in aliases {
                    for source in alias.sources {
                        map[source] = alias.target
                    }
                }
                aliasMap = map
            }
            computeGroupedItems()
        }
    }
}

private struct RankedCard: View {
    let rank: Int
    let name: String
    let score: Double
    let logoPath: String?
    let themeColor: Color
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    var body: some View {
        ZStack {
            if let logoPath, let urlString = APIClient.tmdbImageURL(path: logoPath, size: "w300"), let url = URL(string: urlString) {
                // Logo variant: show logo in normal state, name+score on hover
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                    CachedImage(url: url, targetSize: CGSize(width: 75, height: 32), priority: .low) { _ in
                    } placeholder: {
                        Color.secondary.opacity(0.1)
                    }
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 75, height: 32)
                    .padding(4)
                }
                .frame(width: 85, height: 40)
                .opacity(isHovered ? 0 : 1)
                .scaleEffect(isHovered ? 0.95 : 1.0)

                // Name + score on hover
                VStack(spacing: 4) {
                    Text(name)
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text("\(String(format: "%.0f", score * 100))%")
                        .font(AppTheme.Font.monoCaption)
                        .foregroundStyle(themeColor)
                }
                .opacity(isHovered ? 1 : 0)

            } else {
                // Text variant: always show name, score on hover
                VStack(spacing: 4) {
                    Text(name)
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if isHovered {
                        Text("\(String(format: "%.0f", score * 100))%")
                            .font(AppTheme.Font.monoCaption)
                            .foregroundStyle(themeColor)
                            .transition(.opacity)
                    }
                }
            }

            Text("\(rank)")
                .font(.system(size: 70, weight: .black, design: .rounded))
                .foregroundStyle(themeColor.opacity(isHovered ? 0.22 : 0.10))
                .offset(x: -10, y: -6)
                .allowsHitTesting(false)
        }
        .frame(width: 160, height: 90)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(isHovered ? themeColor.opacity(colorScheme == .dark ? 0.06 : 0.03) : AppTheme.Colors.cardFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(themeColor.opacity(isHovered ? 0.25 : 0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0), radius: 8, y: isHovered ? 4 : 0)
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.springSnappy) { isHovered = hovering }
        }
    }
}
