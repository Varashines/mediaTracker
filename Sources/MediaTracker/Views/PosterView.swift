import SwiftUI

struct PosterView: View {
    let item: MediaItem
    let themeColor: Color
    var namespace: Namespace.ID? = nil

    private let posterFrame = CGSize(width: 260, height: 390)
    @State private var glowPulse = false

    var body: some View {
        if let urlString = item.posterURL, let url = URL(string: urlString) {
            ZStack {
                // 1. Aurora Glow Background — animated radius for breathing effect
                RadialGradient(
                    colors: [themeColor.opacity(0.5), .clear],
                    center: .center,
                    startRadius: glowPulse ? 25 : 20,
                    endRadius: glowPulse ? 260 : 250
                )
                .frame(width: posterFrame.width * 1.38, height: posterFrame.height * 1.26)
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: glowPulse)
                
                let content = CachedImage(url: url, targetSize: .thumbLarge, priority: .normal, themeColor: themeColor) { _ in
                    } placeholder: {
                        Rectangle().fill(Color.secondary.opacity(0.1))
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: posterFrame.width, height: posterFrame.height)
                    .clipped()
                
                Group {
                    if let ns = namespace {
                        content
                            .matchedGeometryEffect(id: "poster_\(item.id)", in: ns)
                            .background {
                                Color.clear.matchedGeometryEffect(id: "poster_bg_\(item.id)", in: ns)
                            }
                    } else {
                        content
                    }
                }
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
        }
    }
}
