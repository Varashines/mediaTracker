import SwiftUI
import SwiftData

struct PosterView: View {
    let item: MediaItem
    let themeColor: Color
    var namespace: Namespace.ID? = nil

    var body: some View {
        if let urlString = item.posterURL, let url = URL(string: urlString) {
            ZStack {
                // 1. Aurora Glow Background (Optimized Gradient instead of Dynamic Blur)
                RadialGradient(
                    colors: [themeColor.opacity(0.4), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 150
                )
                .frame(width: 220, height: 330)
                .offset(y: 10)
                
                let content = CachedImage(url: url, targetSize: .thumbLarge, priority: .critical, themeColor: themeColor) { _ in
                    } placeholder: {
                        Rectangle().fill(Color.secondary.opacity(0.1))
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 240, height: 360)
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
                .frame(width: 240, height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 25, x: 0, y: 15)
                .overlay(alignment: .topLeading) {
                    SmartBadgeView(item: item)
                        .padding(12)
                }
            }
        }
    }
}
