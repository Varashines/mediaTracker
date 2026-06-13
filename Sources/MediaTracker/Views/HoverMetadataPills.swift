import SwiftUI

struct HoverMetadataPills: View {
    let title: String
    let year: String?
    let nextEpisodeLabel: String?
    let nextAiringDate: Date?
    let isUpcoming: Bool
    let isHovered: Bool

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Spacer()

            // Row 1: Name Pill
            HoverPill(text: title, isHovered: isHovered, offset: 20, style: .title)
                .offset(y: isHovered ? 0 : 20)
                .opacity(isHovered ? 1 : 0)

            // Row 2: Consolidated Metadata (Year, Episode, Airing Date)
            HStack(spacing: 6) {
                if let year {
                    HoverPill(text: year, isHovered: isHovered, offset: 30, style: .meta)
                }
                if let episode = nextEpisodeLabel {
                    HoverPill(text: episode, isHovered: isHovered, offset: 30, style: .meta)
                }
                if let nextDate = nextAiringDate, nextDate > Date() {
                    HoverPill(text: nextDate.formatted(.dateTime.month().day()), isHovered: isHovered, offset: 30, style: .meta)
                }
            }
            .offset(y: isHovered ? 0 : 30)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.bottom, 12)
        .padding(.horizontal, 8)
        .animation(AppTheme.Animation.easeInOut, value: isHovered)
    }
}

private enum HoverPillStyle {
    case title, meta
}

private struct HoverPill: View {
    let text: String
    let isHovered: Bool
    let offset: CGFloat
    let style: HoverPillStyle

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Text(text)
            .font(style == .title ? AppTheme.Font.caption2 : .system(size: 8.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, style == .title ? 8 : 6)
            .padding(.vertical, style == .title ? 4 : 3)
            .background(Capsule().fill(.thinMaterial))
            .overlay(
                Capsule()
                    .stroke(.white.opacity(strokeOpacity), lineWidth: 0.5)
            )
    }

    private var strokeOpacity: Double {
        if style == .title {
            return colorScheme == .dark ? 0.15 : 0.45
        }
        return colorScheme == .dark ? 0.1 : 0.3
    }
}
