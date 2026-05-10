import SwiftUI

struct GlassPeekOverlay: View {
    let title: String
    let year: String?
    let state: MediaState?
    let nextEpisodeLabel: String?
    let watchProgress: String?
    let isUpcoming: Bool
    let gridBadgeText: String?
    let isHovered: Bool
    let mode: MediaThumbnailView.DisplayMode
    let appAccent: AppAccent

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: mode == .hero ? 15 : 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
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
                }
                .font(.system(size: mode == .hero ? 11 : 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
        }
        .offset(y: isHovered ? 0 : 120)
        .opacity(isHovered ? 1 : 0)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isHovered)
    }
}
