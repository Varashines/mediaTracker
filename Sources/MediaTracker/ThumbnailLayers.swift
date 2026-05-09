import SwiftUI
import SwiftData

struct ThumbnailPosterLayer: View {
    let posterURL: String?
    let themeColorHex: String?
    let mode: MediaThumbnailView.DisplayMode
    let type: MediaType
    let isFastScrolling: Bool
    let width: CGFloat
    let height: CGFloat
    let namespace: Namespace.ID?
    let capturedID: PersistentIdentifier?
    let resultID: String?

    var body: some View {
        let content = Group {
            if let urlString = posterURL, let url = URL(string: urlString) {
                let baseColor = themeColorHex.flatMap { Color(hex: $0) }
                let targetSize: CGSize = mode == .hero ? .thumbMedium : .thumbSmall
                
                CachedImage(url: url, targetSize: targetSize, themeColor: baseColor, isFastScrolling: isFastScrolling) {
                    _ in
                } placeholder: {
                    Rectangle().fill(Color.secondary.opacity(0.1))
                        .overlay { ProgressView().controlSize(.small) }
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .overlay {
                        Image(systemName: type == .movie ? "film" : "tv")
                            .font(.system(size: mode == .hero ? 40 : 30))
                            .foregroundStyle(.secondary.opacity(0.2))
                    }
                    .frame(width: width, height: height)
            }
        }
        
        content
    }
}
