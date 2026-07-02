import SwiftUI

struct PosterView: View {
    let item: MediaItem
    let themeColor: Color
    let scrollOffset: CGFloat

    private let posterFrame = CGSize(width: 260, height: 390)
    @State private var glowPulse = false

    var body: some View {
        if let urlString = item.posterURL, let url = URL(string: urlString) {
            ZStack {
                // Aurora Glow Background — animated radius for breathing effect
                RadialGradient(
                    colors: [themeColor.opacity(0.5), .clear],
                    center: .center,
                    startRadius: glowPulse ? 25 : 20,
                    endRadius: glowPulse ? 260 : 250
                )
                .frame(width: posterFrame.width * 1.38, height: posterFrame.height * 1.26)
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: glowPulse)

                CachedImage(url: url, targetSize: .thumbMedium, priority: .normal, themeColor: themeColor) { _ in
                } placeholder: {
                        Rectangle().fill(Color.secondary.opacity(0.1)).shimmering()
                            .overlay {
                                Image(systemName: item.type == .movie ? "film" : "tv")
                                    .foregroundStyle(AppTheme.Colors.accent)
                                    .font(.system(size: 24, weight: .medium))
                            }
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: posterFrame.width, height: posterFrame.height)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 8)
                .overlay(alignment: .topLeading) {
                    SmartBadgeView(item: item)
                        .padding(14)
                }
            }
            .compositingGroup()
            .onAppear { glowPulse = true }
            .offset(y: scrollOffset * 0.12)
        }
    }
}
