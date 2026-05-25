import SwiftUI

struct CustomThemePicker: View {
    @Binding var selection: Int
    @Namespace private var segmentNamespace
    @Environment(\.colorScheme) var scheme

    private let options = [
        (0, "Auto", "aqi.medium"),
        (1, "Light", "sun.max.fill"),
        (2, "Dark", "moon.fill")
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { tag, title, icon in
                Button {
                    withAnimation(AppTheme.Animation.springSnappy) {
                        selection = tag
                    }
                    FeedbackManager.shared.trigger(.click)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: icon)
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(title)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minWidth: 64)
                    .contentShape(Rectangle())
                    .background {
                        if selection == tag {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.accentColor)
                                .matchedGeometryEffect(id: "active_theme_segment", in: segmentNamespace)
                                .shadow(color: Color.accentColor.opacity(0.2), radius: 3, x: 0, y: 1)
                        }
                    }
                    .foregroundStyle(selection == tag ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(scheme == .dark ? 0.055 : 0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .help("Auto: Follow system. Light: Always light. Dark: Always dark.")
    }
}
