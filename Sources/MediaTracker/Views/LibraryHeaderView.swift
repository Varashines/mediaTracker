import SwiftUI
import SwiftData

struct LibraryHeaderView: View {
    let selectedNetworks: [String]?
    let onNetworkSelected: ([String]) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
            // Network filter badge
            if let networks = selectedNetworks, let first = networks.first {
                let title = networks.count == 1 ? first : "Merged Studios"

                HStack(spacing: AppTheme.Spacing.tiny) {
                    Text("Filtered by:")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)

                    Text(title)
                        .font(AppTheme.Font.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Button { withAnimation(AppTheme.Animation.springSnappy) { onNetworkSelected([]) } } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppTheme.Icon.medium)
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
    }
}
