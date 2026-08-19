import SwiftUI
import SwiftData

struct LibraryHeaderView: View {
    let selectedNetworks: [String]?
    let onNetworkSelected: ([String]) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
            if let networks = selectedNetworks, let first = networks.first {
                let title = networks.count == 1 ? first : "Merged Studios"

                HStack {
                    Label {
                        Text(title)
                    } icon: {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    }
                    .font(AppTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.accent)
                    .padding(.leading, AppTheme.Spacing.tiny)

                    Button {
                        withAnimation(AppTheme.Animation.springSnappy) {
                            onNetworkSelected([])
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppTheme.Icon.medium)
                            .foregroundStyle(.secondary)
                            .padding(AppTheme.Spacing.micro)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Clear \(title) filter")
                    .accessibilityLabel("Clear \(title) filter")
                }
                .padding(.vertical, AppTheme.Spacing.micro)
                .padding(.trailing, AppTheme.Spacing.micro)
                .background(
                    AppTheme.Colors.accent.opacity(0.12),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(AppTheme.Colors.accent.opacity(0.22), lineWidth: 0.5)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Active filter: \(title)")
                .padding(.top, AppTheme.Spacing.micro)

                if networks.count > 1 {
                    Text("\(networks.count) studios combined")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
    }
}
