import SwiftUI
import SwiftData

struct PosterView: View {
    let item: MediaItem
    let themeColor: Color
    var namespace: Namespace.ID? = nil

    var body: some View {
        if let urlString = item.posterURL, let url = URL(string: urlString) {
            ZStack {
                // 1. Aurora Glow Background
                RadialGradient(
                    colors: [themeColor.opacity(0.5), .clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: 250
                )
                .frame(width: 360, height: 490)
                
                let content = CachedImage(url: url, targetSize: .thumbLarge, priority: .critical, themeColor: themeColor) { _ in
                    } placeholder: {
                        Rectangle().fill(Color.secondary.opacity(0.1))
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 260, height: 390)
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
                .frame(width: 260, height: 390)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 20)
                .overlay(alignment: .topLeading) {
                    SmartBadgeView(item: item, themeColor: themeColor)
                        .padding(14)
                }
            }
        }
    }
}
