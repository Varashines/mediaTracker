import SwiftUI

struct ThumbnailHoverOverlay: View {
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
        VStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: mode == .hero ? 18 : 13, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 4)
            
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
            .font(.system(size: mode == .hero ? 12 : 10, weight: .bold, design: .rounded))
            .kerning(1.0)
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.6), radius: 2)
            
            if isUpcoming, let date = gridBadgeText {
                Text(date.uppercased())
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .kerning(1.5)
                    .padding(.top, 4)
                    .foregroundStyle(date.contains("STREAMING") ? appAccent.color : .white)
                    .shadow(color: .black.opacity(0.4), radius: 2)
            }
        }
        .padding(.horizontal, 12)
        .opacity(isHovered ? 1 : 0)
        .scaleEffect(isHovered ? 1.0 : 0.9)
    }
}

struct ThumbnailSearchOverlay: View {
    let isAdded: Bool
    let isLocalInSearch: Bool
    let isHovered: Bool

    var body: some View {
        if isAdded {
            ZStack {
                if !isLocalInSearch {
                    Rectangle()
                        .fill(.black.opacity(0.6))
                    
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.green)
                        Text("In Library")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                } else if isHovered {
                    Rectangle()
                        .fill(.black.opacity(0.2))
                }
            }
        } else if isHovered {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                        .padding(12)
                }
            }
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .top, endPoint: .bottom)
            )
        }
    }
}
