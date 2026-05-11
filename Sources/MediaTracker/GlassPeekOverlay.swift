import SwiftUI

struct GlassPeekOverlay: View {
    let title: String
    let year: String?
    let state: MediaState?
    let nextEpisodeLabel: String?
    let watchProgress: String?
    let nextAiringDate: Date?
    let isUpcoming: Bool
    let gridBadgeText: String?
    let isHovered: Bool
    let mode: MediaThumbnailView.DisplayMode
    let appAccent: AppAccent
    
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: mode == .hero ? 14 : 11, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                
                HStack(spacing: 6) {
                    if let year = year {
                        Text(year)
                    }
                    
                    if state != .completed {
                        let currentInfo = nextEpisodeLabel ?? watchProgress
                        if let info = currentInfo {
                            Text("•")
                            Text(info)
                        }
                    }
                    
                    if let nextDate = nextAiringDate, nextDate > Date() {
                        Text("•")
                        Text(nextDate.formatted(.dateTime.month().day()))
                            .foregroundStyle(appAccent.color(for: colorScheme))
                    }
                }
                .font(.system(size: mode == .hero ? 10 : 8, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
        }
        .offset(y: isHovered ? 0 : 120)
        .opacity(isHovered ? 1 : 0)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isHovered)
    }
}
