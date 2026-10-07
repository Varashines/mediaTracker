import SwiftUI

struct HoverMetadataPills: View, Equatable {
    let title: String
    let year: String?
    let nextEpisodeLabel: String?
    let nextAiringDate: Date?
    let isUpcoming: Bool
    let isHovered: Bool

    @Environment(\.colorScheme) var colorScheme
    
    nonisolated static func == (lhs: HoverMetadataPills, rhs: HoverMetadataPills) -> Bool {
        lhs.title == rhs.title && lhs.year == rhs.year &&
        lhs.nextEpisodeLabel == rhs.nextEpisodeLabel && lhs.nextAiringDate == rhs.nextAiringDate &&
        lhs.isUpcoming == rhs.isUpcoming && lhs.isHovered == rhs.isHovered
    }

    var body: some View {
        // Off-hover: return nothing — zero pills, materials, or shadows to
        // composite while the grid is idle (the common case).
        if isHovered {
            VStack(spacing: 8) {
                Spacer()

                HoverPill(text: title, style: .title)

                HStack(spacing: 6) {
                    if let year {
                        HoverPill(text: year, style: .meta)
                    }
                    if let episode = nextEpisodeLabel {
                        HoverPill(text: episode, style: .meta)
                    }
                    if let nextDate = nextAiringDate, nextDate > Date() {
                        HoverPill(text: nextDate.formatted(.dateTime.month().day()), style: .meta)
                    }
                }
            }
            .padding(.bottom, 12)
            .padding(.horizontal, 8)
            .transition(.opacity.combined(with: .offset(y: 12)))
            .animation(AppTheme.Animation.springSnappy, value: isHovered)
        }
    }
}

enum HoverPillStyle {
    case title, meta
}

struct HoverPill: View {
    let text: String
    var icon: String? = nil
    let style: HoverPillStyle

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
            }
            Text(text)
        }
        .font(style == .title ? AppTheme.Font.caption2 : AppTheme.Font.metadataChip)
            // Capsule fill is always near-black — .primary would be black-on-black in light mode.
            .foregroundStyle(.white)
            .padding(.horizontal, style == .title ? AppTheme.Spacing.tiny : AppTheme.Spacing.mini)
            .padding(.vertical, style == .title ? AppTheme.Spacing.micro : 3)
            // Flat translucent fill — only rendered on hover now, but a
            // material here still forces an offscreen pass per pill.
            .background(Capsule().fill(Color.black.opacity(colorScheme == .dark ? 0.55 : 0.72)))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(strokeOpacity), lineWidth: 0.5)
            )
    }

    private var strokeOpacity: Double {
        if style == .title {
            return colorScheme == .dark ? 0.2 : 0.35
        }
        return colorScheme == .dark ? 0.12 : 0.25
    }
}
