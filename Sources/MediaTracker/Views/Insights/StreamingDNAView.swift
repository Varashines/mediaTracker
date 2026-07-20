import SwiftUI
import SwiftData

struct StreamingDNAView: View {
    let stats: LibraryStats
    let modelContext: ModelContext

    @State private var logoMap: [String: String] = [:]
    @State private var colorMap: [String: String] = [:]
    @State private var aliasMap: [String: String] = [:]
    @State private var cachedStudioItems: [(String, Double, String?, String?)] = []
    @State private var cachedNetworkItems: [(String, Double, String?, String?)] = []
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: AppTheme.Spacing.large), GridItem(.flexible(), spacing: AppTheme.Spacing.large)], spacing: AppTheme.Spacing.large) {
            
            // 1. Top Providers (Cozy Streams)
            GlassCard(color: .blue) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    HStack(spacing: 6) {
                        Text("📺")
                            .font(.title3)
                        Text("COZY STREAMS")
                            .font(AppTheme.Font.caption)
                            .kerning(AppTheme.Kerning.wide)
                            .foregroundStyle(.blue.opacity(0.85))
                        Spacer()
                    }
                    
                    if stats.topProviders.isEmpty {
                        CuteEmptyState(icon: "tv.and.mediabox", message: "No streams yet", color: .blue)
                            .frame(height: 100)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(stats.topProviders.prefix(3).enumerated()), id: \.offset) { idx, item in
                                HStack(spacing: AppTheme.Spacing.small) {
                                    Circle()
                                        .fill(Color.blue.opacity(0.15))
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Text("\(idx + 1)")
                                                .font(AppTheme.Font.monoCaption)
                                                .foregroundStyle(.blue)
                                        )
                                    Text(item.name)
                                        .font(AppTheme.Font.bodyBold)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(item.count) titles")
                                        .font(AppTheme.Font.label)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(AppTheme.Spacing.medium)
            }
            
            // 2. Top Studios (Creative Hubs)
            GlassCard(color: .orange) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    HStack(spacing: 6) {
                        Text("🎬")
                            .font(.title3)
                        Text("CREATIVE HUBS")
                            .font(AppTheme.Font.caption)
                            .kerning(AppTheme.Kerning.wide)
                            .foregroundStyle(.orange.opacity(0.85))
                        Spacer()
                    }
                    
                    if cachedStudioItems.isEmpty {
                        CuteEmptyState(icon: "building.2", message: "No studios yet", color: .orange)
                            .frame(height: 100)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(cachedStudioItems.prefix(3).enumerated()), id: \.offset) { idx, item in
                                HStack(spacing: AppTheme.Spacing.small) {
                                    Circle()
                                        .fill(Color.orange.opacity(0.15))
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Text("\(idx + 1)")
                                                .font(AppTheme.Font.monoCaption)
                                                .foregroundStyle(.orange)
                                        )
                                    Text(item.0)
                                        .font(AppTheme.Font.bodyBold)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(String(format: "%.0f%%", item.1 * 100))
                                        .font(AppTheme.Font.monoCaption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(AppTheme.Spacing.medium)
            }

            // 3. Top Networks (Tuning In)
            GlassCard(color: .teal) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    HStack(spacing: 6) {
                        Text("📡")
                            .font(.title3)
                        Text("TUNING IN")
                            .font(AppTheme.Font.caption)
                            .kerning(AppTheme.Kerning.wide)
                            .foregroundStyle(.teal.opacity(0.85))
                        Spacer()
                    }
                    
                    if cachedNetworkItems.isEmpty {
                        CuteEmptyState(icon: "antenna.radiowaves.left.and.right", message: "No networks yet", color: .teal)
                            .frame(height: 100)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(cachedNetworkItems.prefix(3).enumerated()), id: \.offset) { idx, item in
                                HStack(spacing: AppTheme.Spacing.small) {
                                    Circle()
                                        .fill(Color.teal.opacity(0.15))
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Text("\(idx + 1)")
                                                .font(AppTheme.Font.monoCaption)
                                                .foregroundStyle(.teal)
                                        )
                                    Text(item.0)
                                        .font(AppTheme.Font.bodyBold)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(String(format: "%.0f%%", item.1 * 100))
                                        .font(AppTheme.Font.monoCaption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(AppTheme.Spacing.medium)
            }

            // 4. Global Speech (Languages)
            GlassCard(color: .purple) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    HStack(spacing: 6) {
                        Text("🌐")
                            .font(.title3)
                        Text("GLOBAL SPEECH")
                            .font(AppTheme.Font.caption)
                            .kerning(AppTheme.Kerning.wide)
                            .foregroundStyle(.purple.opacity(0.85))
                        Spacer()
                    }
                    
                    if stats.topRatedLanguages.isEmpty {
                        CuteEmptyState(icon: "globe", message: "No language yet", color: .purple)
                            .frame(height: 100)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(stats.topRatedLanguages.prefix(3).enumerated()), id: \.offset) { idx, item in
                                HStack(spacing: AppTheme.Spacing.small) {
                                    Circle()
                                        .fill(Color.purple.opacity(0.15))
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Text("\(idx + 1)")
                                                .font(AppTheme.Font.monoCaption)
                                                .foregroundStyle(.purple)
                                        )
                                    Text(item.name)
                                        .font(AppTheme.Font.bodyBold)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(String(format: "%.0f%%", item.1 * 100))
                                        .font(AppTheme.Font.monoCaption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(AppTheme.Spacing.medium)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
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
                    for source in alias.sources { map[source] = alias.target }
                }
                aliasMap = map
            }
            cachedStudioItems  = groupedItems(stats.topRatedStudios)
            cachedNetworkItems = groupedItems(stats.topRatedNetworks)
        }
    }

    private func groupedItems(_ items: [(name: String, score: Double)]) -> [(String, Double, String?, String?)] {
        var grouped: [String: (score: Double, logoPath: String?, themeColorHex: String?)] = [:]
        for (name, score) in items {
            let target = aliasMap[name] ?? name
            if let existing = grouped[target] {
                grouped[target] = (
                    score: max(existing.score, score),
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
            .prefix(3)
            .map { $0 }
    }
}
