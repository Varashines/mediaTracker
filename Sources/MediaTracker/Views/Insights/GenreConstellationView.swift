import SwiftUI

struct GenreConstellationView: View {
    let items: [(name: String, percentage: Double)]

    var body: some View {
        if items.isEmpty {
            CuteEmptyState(icon: "sparkles.magnifyingglass", message: "Discover more genres!", color: .indigo)
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 16) {
                ForEach(Array(items.prefix(6).enumerated()), id: \.element.name) { idx, item in
                    let node = DiscoveryNode(
                        name: item.name,
                        logoPath: nil,
                        count: idx + 1,
                        themeColorHex: nil
                    )
                    DiscoveryCard(node: node, style: .text, baseColor: .indigo) { }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
        }
    }
}
