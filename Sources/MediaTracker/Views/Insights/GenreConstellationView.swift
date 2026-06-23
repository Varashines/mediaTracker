import SwiftUI

struct GenreConstellationView: View {
    let items: [(name: String, percentage: Double)]

    var body: some View {
        if items.isEmpty {
            CuteEmptyState(icon: "sparkles.magnifyingglass", message: "Discover more genres!", color: .indigo)
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: AppTheme.Spacing.large)], spacing: AppTheme.Spacing.large) {
                ForEach(Array(items.prefix(6).enumerated()), id: \.element.name) { idx, item in
                    let node = DiscoveryNode(
                        name: item.name,
                        logoPath: nil,
                        count: idx + 1,
                        themeColorHex: nil
                    )
                    DiscoveryCard(node: node, style: .text, baseColor: .indigo) { }
                        .modifier(StaggerModifier(index: idx))
                }
            }
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
        }
    }
}

private struct StaggerModifier: ViewModifier {
    let index: Int
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 8)
            .onAppear {
                if !hasAppeared {
                    withAnimation(AppTheme.Animation.springGentle.delay(Double(index % 6) * 0.05)) {
                        hasAppeared = true
                    }
                }
            }
    }
}
