import SwiftUI

struct OverviewSection: View {
    let overview: String
    let themeColor: Color
    /// Opens the full synopsis in a staged modal (DetailView level), which also
    /// lists genres. Nil hides the info button.
    var onExpand: (() -> Void)? = nil

    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false

    private var surfaceColor: Color {
        AppTheme.Colors.surfaceGhost(for: colorScheme)
    }

    private var isTruncated: Bool {
        overview.count > 200
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.mini) {
            HStack(spacing: AppTheme.Spacing.tiny) {
                Image(systemName: "quote.opening")
                    .font(AppTheme.Font.title)
                    .foregroundStyle(themeColor.highContrastAccent(colorScheme: colorScheme))

                Text("SYNOPSIS")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .kerning(AppTheme.Kerning.wide)

                Spacer()

                // Always offered, not just for a truncated synopsis: this popup is
                // also where genres live, so gating it on length left short
                // synopses with no way to reach them.
                if let onExpand {
                    Button {
                        onExpand()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(isHovering ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .help("More about this title")
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(overview)
                    .font(AppTheme.Font.bodyMedium)
                    .lineSpacing(AppTheme.Spacing.tiny)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .mask(
                        LinearGradient(
                            stops: isTruncated
                                ? [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 0.6),
                                    .init(color: .clear, location: 1)
                                ]
                                : [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 1)
                                ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.grid)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                // Flat fill — material blur on the synopsis card re-rasterized
                // on every Detail scroll frame.
                .fill(AppTheme.Colors.surfaceGhost(for: colorScheme))
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 0.5)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
