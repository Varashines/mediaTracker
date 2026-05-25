import SwiftUI

struct CustomNotificationCheckbox: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    @Environment(\.colorScheme) var scheme

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                isOn.toggle()
            }
            FeedbackManager.shared.trigger(.click)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isOn ? Color.accentColor : Color.primary.opacity(0.04))
                        .frame(width: 18, height: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(isOn ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 0.75)
                        )

                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                Label(title, systemImage: icon)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(isOn ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .scaleEffect(isOn ? 1 : 0.975)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isOn)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.05) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isOn ? Color.accentColor.opacity(0.15) : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
