import SwiftUI

// MARK: - Card (grouped section)

struct SettingsCard<Content: View>: View {
    var color: Color = .clear
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) var scheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(scheme == .dark ? Color(white: 0.12) : Color(white: 0.96))
            )

            // Subtle colored accent strip
            if color != .clear {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
            }
        }
    }
}

// MARK: - SettingsRow

struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var showDivider: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                trailing()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if showDivider {
                Divider().opacity(0.06).padding(.leading, 16)
            }
        }
    }
}

// MARK: - SectionHeader

struct SettingsSectionHeader: View {
    let text: String
    var color: Color = .primary

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
    }
}

// MARK: - SettingsToggleRow

struct SettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    var showDivider: Bool = true
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, showDivider: showDivider) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                isOn.toggle()
            }
        }
    }
}

// MARK: - SettingsButton

struct SettingsButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - StatusBadge

struct StatusBadge: View {
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? Color.green : Color.red)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(isActive ? Color.green : Color.red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background((isActive ? Color.green : Color.red).opacity(0.08))
        .clipShape(Capsule())
    }
}
