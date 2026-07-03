import SwiftUI

struct DiscoverySection<HeaderAccessory: View>: View {
    let title: String
    let icon: String
    let nodes: [DiscoveryNode]
    let style: DiscoveryCardStyle
    let isFastScrolling: Bool
    var limit: Int? = nil
    @ViewBuilder var headerAccessory: () -> HeaderAccessory
    let onSelected: (DiscoveryNode) -> Void
    
    @State private var isExpanded = false
    
    var sectionColor: Color {
        switch title {
        case "Genres": return .indigo
        case "Languages": return .teal
        case "Recent Activity": return .purple
        default: return .gray
        }
    }
    
    private var displayedNodes: [DiscoveryNode] {
        guard let limit, !isExpanded else { return nodes }
        return Array(nodes.prefix(limit))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            HStack(spacing: 0) {
                SectionHeader(title: title, icon: icon, iconColor: sectionColor)
                
                headerAccessory()
                    .padding(.leading, AppTheme.Spacing.small)
                
                Spacer()
                
                if let limit, nodes.count > limit {
                    Button {
                        withAnimation(AppTheme.Animation.springSnappy) { isExpanded.toggle() }
                    } label: {
                        Text(isExpanded ? "Less" : "+\(nodes.count - limit)")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .padding(.trailing, AppTheme.Spacing.pageMargin)
                }
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: AppTheme.Spacing.large)], spacing: AppTheme.Spacing.large) {
                ForEach(Array(displayedNodes.enumerated()), id: \.element.id) { index, node in
                    DiscoveryCard(node: node, style: style, baseColor: sectionColor) { onSelected(node) }
                        .modifier(StaggerModifier(index: index, isFastScrolling: isFastScrolling))
                }
            }
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
        }
    }
}

// MARK: - No-Accessory Convenience

extension DiscoverySection where HeaderAccessory == EmptyView {
    init(title: String, icon: String, nodes: [DiscoveryNode], style: DiscoveryCardStyle, isFastScrolling: Bool, limit: Int? = nil, onSelected: @escaping (DiscoveryNode) -> Void) {
        self.title = title
        self.icon = icon
        self.nodes = nodes
        self.style = style
        self.isFastScrolling = isFastScrolling
        self.limit = limit
        self.headerAccessory = { EmptyView() }
        self.onSelected = onSelected
    }
}
