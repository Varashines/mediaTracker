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
            // Studios (with alias grouping)
            let studioItems = cachedStudioItems
            if !studioItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "building.2.fill")
                            .font(AppTheme.Font.heading)
                            .foregroundStyle(.orange)
                        Text("Studios")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.orange)
                            .kerning(1.2)
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(Array(studioItems.enumerated()), id: \.0) { idx, item in
                                let node = DiscoveryNode(
                                    name: item.0,
                                    logoPath: item.2,
                                    count: idx + 1,
                                    themeColorHex: item.3
                                )
                                if item.2 != nil {
                                    DiscoveryCard(node: node, style: .logo) { }
                                        .frame(width: 160, height: 90)
                                } else {
                                    DiscoveryCard(node: node, style: .text, baseColor: .orange) { }
                                }
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        .padding(.vertical, 4)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }

            // Networks (with alias grouping)
            let networkItems = cachedNetworkItems
            if !networkItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(AppTheme.Font.heading)
                            .foregroundStyle(.teal)
                        Text("Networks")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.teal)
                            .kerning(1.2)
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(Array(networkItems.enumerated()), id: \.0) { idx, item in
                                let node = DiscoveryNode(
                                    name: item.0,
                                    logoPath: item.2,
                                    count: idx + 1,
                                    themeColorHex: item.3
                                )
                                if item.2 != nil {
                                    DiscoveryCard(node: node, style: .logo) { }
                                        .frame(width: 160, height: 90)
                                } else {
                                    DiscoveryCard(node: node, style: .text, baseColor: .teal) { }
                                }
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
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(AppTheme.Font.heading)
                            .foregroundStyle(.purple)
                        Text("Languages")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.purple)
                            .kerning(1.2)
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 16) {
                        ForEach(Array(stats.topRatedLanguages.prefix(6).enumerated()), id: \.element.name) { idx, item in
                            let node = DiscoveryNode(
                                name: item.name,
                                logoPath: nil,
                                count: idx + 1,
                                themeColorHex: nil
                            )
                            DiscoveryCard(node: node, style: .text, baseColor: .purple) { }
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
