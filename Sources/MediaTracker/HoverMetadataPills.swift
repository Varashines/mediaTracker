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
                .font(.system(size: 10.5, weight: .black, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor)
                .clipShape(Capsule())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                .offset(y: isHovered ? 0 : 20)
                .opacity(isHovered ? 1 : 0)
            
            // Row 2: Consolidated Metadata (Year, Episode, Airing Date)
            HStack(spacing: 6) {
                if let year = year {
                    Text(year)
                        .font(.system(size: 8.5, weight: .black, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                
                if let episode = nextEpisodeLabel {
                    Text(episode)
                        .font(.system(size: 8.5, weight: .black, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                
                if let nextDate = nextAiringDate, nextDate > Date() {
                    Text(nextDate.formatted(.dateTime.month().day()))
                        .font(.system(size: 8.5, weight: .black, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            .offset(y: isHovered ? 0 : 30)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.bottom, 12)
        .padding(.horizontal, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isHovered)
    }
}
