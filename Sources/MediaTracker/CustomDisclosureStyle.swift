import SwiftUI

struct CustomDisclosureStyle: DisclosureGroupStyle {
    let buttonColor: Color
    
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            Button {
                // High-response spring for the toggle
                withAnimation(.smooth) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                configuration.label
                    .contentShape(Rectangle())
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            
            if configuration.isExpanded {
                configuration.content
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.98, anchor: .top))
                                .combined(with: .move(edge: .top)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.95))
                        )
                    )
            }
        }
    }
}
