import SwiftUI

struct CapsuleTabBar<Tab: Hashable & Identifiable>: View {
    @Binding var selection: Tab
    var tabs: [Tab]
    var icons: [Tab: String]
    var namespace: Namespace.ID
    var label: (Tab) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                Button {
                    withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.8)) {
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let icon = icons[tab] {
                            Image(systemName: icon)
                                .font(.system(size: 11, weight: .medium))
                        }
                        Text(label(tab))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        ZStack {
                            if selection == tab {
                                Capsule()
                                    .fill(.primary.opacity(0.08))
                                    .matchedGeometryEffect(id: "activeTab", in: namespace)
                            }
                        }
                    )
                    .foregroundStyle(
                        selection == tab
                            ? Color.primary
                            : Color.secondary.opacity(0.6)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.ultraThinMaterial.opacity(0.6))
        .clipShape(Capsule())
    }
}
