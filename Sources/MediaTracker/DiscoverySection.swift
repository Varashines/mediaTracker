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
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: title, icon: icon, iconColor: sectionColor)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 24)], spacing: 24) {
                ForEach(nodes) { node in
                    DiscoveryCard(node: node, style: style, baseColor: sectionColor) { onSelected(node) }
                }
            }
            .padding(.horizontal, 40)
        }
    }
}
