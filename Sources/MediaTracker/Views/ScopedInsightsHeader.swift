import SwiftUI
import SwiftData

struct ScopedInsightsHeader: View {
    let stats: ScopedLibraryStats
    let filterName: String
    let filterType: FilterType
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var logoMap: [String: String] = [:]
    @State private var themeColorMap: [String: String] = [:]

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: AppTheme.Spacing.large)]

    private var hasAnySection: Bool {
        if stats.topActors.count > 1 { return true }
        if filterType != .genre && stats.topGenres.count > 1 { return true }
        if filterType != .network && filterType != .studio && stats.topNetworks.count > 1 { return true }
        if filterType != .provider && stats.topProviders.count > 1 { return true }
        if filterType != .language && stats.topLanguages.count > 1 { return true }
        return false
    }

    @ViewBuilder
    var body: some View {
        if hasAnySection {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                if stats.topActors.count > 1 {
                    actorSection
                }
                if filterType != .genre && stats.topGenres.count > 1 {
                    genreSection
                }
                if filterType != .network && filterType != .studio && stats.topNetworks.count > 1 {
                    networkSection
                }
                if filterType != .provider && stats.topProviders.count > 1 {
                    providerSection
                }
                if filterType != .language && stats.topLanguages.count > 1 {
                    languageSection
                }
            }
            .padding(AppTheme.Spacing.xLarge)
            .background(AppTheme.Colors.cardFill(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 0.8)
            )
            .task {
                await loadLogos()
            }
        }
    }

    // MARK: - Top Cast (Detail View style — horizontal cast cards)

    private var actorSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            headerLabel("Top Cast")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: AppTheme.Spacing.medium) {
                    ForEach(stats.topActors.prefix(6)) { actor in
                        CastMemberCard(
                            member: SimpleCastMember(
                                id: actor.name,
                                name: actor.name,
                                characterName: "",
                                profileURL: actor.profileURL,
                                order: 0
                            ),
                            themeColor: AppTheme.Colors.accent
                        )
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.compact)
                .padding(.vertical, AppTheme.Spacing.small)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: - Top Genres (Discovery text style)

    private var genreSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            headerLabel("Top Genres")
            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.large) {
                ForEach(stats.topGenres.prefix(6), id: \.name) { genre in
                    let node = DiscoveryNode(
                        name: genre.name,
                        logoPath: nil,
                        count: Int(genre.score * 100),
                        themeColorHex: nil
                    )
                    DiscoveryCard(node: node, style: .text, baseColor: .indigo) {}
                }
            }
        }
    }

    // MARK: - Top Networks (count-based)

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            headerLabel("Top Networks")
            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.large) {
                ForEach(stats.topNetworks.prefix(6), id: \.name) { net in
                    let node = DiscoveryNode(
                        name: net.name,
                        logoPath: logoMap[net.name],
                        count: net.count,
                        themeColorHex: themeColorMap[net.name]
                    )
                    DiscoveryCard(node: node, style: .logo, baseColor: .gray) {}
                }
            }
        }
    }

    // MARK: - Top Providers (count-based)

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            headerLabel("Top Providers")
            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.large) {
                ForEach(stats.topProviders.prefix(6), id: \.name) { prov in
                    let node = DiscoveryNode(
                        name: prov.name,
                        logoPath: logoMap[prov.name],
                        count: prov.count,
                        themeColorHex: nil
                    )
                    DiscoveryCard(node: node, style: .logo, baseColor: .gray) {}
                }
            }
        }
    }

    // MARK: - Top Languages (Discovery text style)

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            headerLabel("Top Languages")
            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.large) {
                ForEach(stats.topLanguages.prefix(6), id: \.name) { lang in
                    let displayName = LanguageUtils.languageName(for: lang.name)
                    let node = DiscoveryNode(
                        name: displayName,
                        logoPath: nil,
                        count: lang.count,
                        themeColorHex: nil
                    )
                    DiscoveryCard(node: node, style: .text, baseColor: .teal) {}
                }
            }
        }
    }

    private func headerLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.Font.caption2)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func loadLogos() async {
        // Fetch network logos and colors
        let networkNames = Set(stats.topNetworks.map(\.name))
        let networkDesc = FetchDescriptor<NetworkEntity>(predicate: #Predicate { networkNames.contains($0.name) })
        if let networks = try? modelContext.fetch(networkDesc) {
            for net in networks {
                if let logo = net.logoPath { logoMap[net.name] = logo }
                if let hex = net.themeColorHex { themeColorMap[net.name] = hex }
            }
        }
        // Fetch provider logos
        let providerNames = Set(stats.topProviders.map(\.name))
        let providerDesc = FetchDescriptor<ProviderEntity>(predicate: #Predicate { providerNames.contains($0.name) })
        if let providers = try? modelContext.fetch(providerDesc) {
            for prov in providers where prov.logoPath != nil {
                logoMap[prov.name] = prov.logoPath
            }
        }
    }
}
