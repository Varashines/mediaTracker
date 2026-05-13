import SwiftUI
import SwiftData

struct ForYouCompactCard: View {
    let metadata: MediaThumbnailMetadata
    let namespace: Namespace.ID
    var isFastScrolling: Bool = false
    @State private var isHovered = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @State private var item: MediaItem?
    
    private let cardWidth: CGFloat = 420
    private let cardHeight: CGFloat = 200

    var body: some View {
        ZStack(alignment: .leading) {
            // 1. Background Layer (Backdrop with Glass)
            if let backdrop = metadata.backdropURL, let url = URL(string: backdrop) {
                CachedImage(url: url, targetSize: .backdropLarge, isFastScrolling: isFastScrolling) { _ in } placeholder: {
                    Rectangle().fill(Color.secondary.opacity(0.1))
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: cardWidth, height: cardHeight)
                .clipped()
                .overlay(Color.black.opacity(isHovered ? 0.2 : 0.4))
            } else {
                Rectangle().fill(Color.black.opacity(0.8))
                    .frame(width: cardWidth, height: cardHeight)
            }
            
            HStack(spacing: 20) {
                // 2. Floating Poster (The "Hero" element)
                if let poster = metadata.posterURL, let url = URL(string: poster) {
                    CachedImage(url: url, targetSize: .thumbMedium, isFastScrolling: isFastScrolling) { _ in } placeholder: {
                        Rectangle().fill(Color.secondary.opacity(0.1))
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.6), radius: 10, x: 5, y: 5)
                    .scaleEffect(isHovered ? 1.05 : 1.0)
                }

                // 3. Info Pane
                VStack(alignment: .leading, spacing: 8) {
                    Text(metadata.title)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(radius: 2)
                    
                    Text(metadata.formattedMetadata)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))

                    if let reason = recommendationContext {
                        Text(reason)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                            .padding(.top, 4)
                    }
                }
                .padding(.trailing, 20)
            }
            .padding(.leading, 20)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(isHovered ? 0.3 : 0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(isHovered ? 0.4 : 0.2), radius: 15, y: 10)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
        .task {
            if let fetched = modelContext.model(for: metadata.id) as? MediaItem {
                self.item = fetched
            }
        }
    }
    
    private var recommendationContext: String? {
        if let reason = metadata.recommendationReason { return reason }
        guard let item = item else { return nil }
        
        let creators = item.cachedCreators
        if let firstCreator = creators.first {
            return "\(item.type == .movie ? "Directed by" : "Created by") \(firstCreator)"
        }
        
        let cast = item.storedCast
        if let firstActor = cast.sorted(by: { $0.order < $1.order }).first {
            return "Starring \(firstActor.name)"
        }
        
        if let firstGenre = metadata.genres.first {
            return "\(firstGenre) Selection"
        }
        
        return "Picked for you"
    }
}
