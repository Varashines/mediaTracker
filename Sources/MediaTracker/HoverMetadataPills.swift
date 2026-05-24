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
            Text(title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(colorScheme == .dark ? 0.15 : 0.45), lineWidth: 0.5)
                )
                .offset(y: isHovered ? 0 : 20)
                .opacity(isHovered ? 1 : 0)
            
            // Row 2: Consolidated Metadata (Year, Episode, Airing Date)
            HStack(spacing: 6) {
                if let year = year {
                    Text(year)
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(colorScheme == .dark ? 0.1 : 0.3), lineWidth: 0.5)
                        )
                }
                
                if let episode = nextEpisodeLabel {
                    Text(episode)
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(colorScheme == .dark ? 0.1 : 0.3), lineWidth: 0.5)
                        )
                }
                
                if let nextDate = nextAiringDate, nextDate > Date() {
                    Text(nextDate.formatted(.dateTime.month().day()))
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(colorScheme == .dark ? 0.1 : 0.3), lineWidth: 0.5)
                        )
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
