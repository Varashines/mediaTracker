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
        case "Recent Activity": return .purple
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            SectionHeader(title: title, icon: icon, iconColor: sectionColor)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: AppTheme.Spacing.large)], spacing: AppTheme.Spacing.large) {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    DiscoveryCard(node: node, style: style, baseColor: sectionColor) { onSelected(node) }
                        .modifier(StaggerModifier(index: index))
                }
            }
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
        }
    }
}

// MARK: - Stagger Modifier

private struct StaggerModifier: ViewModifier {
    let index: Int
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 8)
            .onAppear {
                if !hasAppeared {
                    withAnimation(AppTheme.Animation.springGentle.delay(Double(index % 8) * 0.05)) {
                        hasAppeared = true
                    }
                }
            }
    }
}
