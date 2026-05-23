import SwiftUI

struct DiscoverySection: View {
    let title: String
    let icon: String
    let nodes: [DiscoveryNode]
    let style: DiscoveryCardStyle
    let onSelected: (DiscoveryNode) -> Void
    
    var sectionColor: Color {
        switch title {
        case "Genres": return .indigo
        case "Languages": return .teal
        default: return .accentColor
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            SectionHeader(title: title, icon: icon, iconColor: sectionColor)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: AppTheme.Spacing.large)], spacing: AppTheme.Spacing.large) {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    DiscoveryCard(node: node, style: style, baseColor: sectionColor) { onSelected(node) }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.xLarge + AppTheme.Spacing.tiny)
        }
    }
}
