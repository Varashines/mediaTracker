import SwiftUI
import SwiftData

struct HomeHeroCard: View {
    let metadata: MediaThumbnailMetadata
    let namespace: Namespace.ID
    var isFastScrolling: Bool = false
    @State private var isHovered = false
    @Environment(\.modelContext) private var modelContext
    @State private var item: MediaItem?
    
    var body: some View {
        ZStack(alignment: .leading) {
            // 1. Cinematic Backdrop (Blurred & Darkened)
            if let backdrop = metadata.backdropURL, let url = URL(string: backdrop) {
                CachedImage(url: url, targetSize: .backdropLarge, isFastScrolling: isFastScrolling) { _ in } placeholder: {
                    Rectangle().fill(Color.secondary.opacity(0.1))
                        .overlay { ProgressView().controlSize(.small) }
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 500, height: 280)
                .clipped()
                .overlay(Color.black.opacity(isHovered ? 0.5 : 0.4))
            } else {
                Rectangle().fill(Color.black.opacity(0.8))
                    .frame(width: 500, height: 280)
            }
            
            // 2. Matching Your Taste Tag (Top Right)
            if let context = recommendationContext {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 10, weight: .semibold))
                            Text(context.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(1.2)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .opacity(0.9)
                        }
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
                        .padding(24)
                    }
                    Spacer()
                }
            }
            
            HStack(spacing: 24) {
                // 3. Floating Vertical Poster (3D Depth)
                if let poster = metadata.posterURL, let url = URL(string: poster) {
                    CachedImage(url: url, targetSize: .thumbMedium, isFastScrolling: isFastScrolling) { _ in } placeholder: {
                        Rectangle().fill(Color.secondary.opacity(0.1))
                            .overlay { ProgressView().controlSize(.small) }
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 140, height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 10)
                    .overlay(alignment: .topLeading) {
                        SmartBadgeView(metadata: metadata, hideEpisodeProgress: true)
                            .padding(8)
                            .opacity(isHovered ? 0 : 1)
                    }
                }
                
                // 4. Immersive Details (Right Side)
                VStack(alignment: .leading, spacing: 6) {
                    if metadata.isUpcoming {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.yellow)
                            .padding(.bottom, 2)
                    }
                    
                    Text(metadata.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                    
                    Text(metadata.formattedMetadata)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.5), radius: 2)
                }
                .padding(.trailing, 20)
                
                Spacer()
            }
            .padding(.leading, 30)
        }
        .frame(width: 500, height: 280)
        .cornerRadius(24)
        .shadow(color: .black.opacity(isHovered ? 0.2 : 0.08), radius: 10, y: 5)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
        .task {
            // Phase 2 Optimization: Lazy Load the full item for recommendation context
            if let fetched = modelContext.model(for: metadata.id) as? MediaItem {
                self.item = fetched
            }
        }
    }
    
    private var recommendationContext: String? {
        // Priority 0: Explicit Recommendation Reason from Taste Engine
        if let reason = metadata.recommendationReason {
            return reason
        }

        guard let item = item, item.modelContext != nil else { return nil }
        
        // Priority 1: Creators/Directors
        let creators = item.cachedCreators
        if let firstCreator = creators.first {
            return "\(item.type == .movie ? "Directed by" : "Created by") \(firstCreator)"
        }
        
        // Priority 2: Leading Cast
        let cast = item.storedCast
        if let firstActor = cast.sorted(by: { $0.order < $1.order }).first {
            return "Starring \(firstActor.name)"
        }
        
        // Priority 3: Primary Genre
        if let firstGenre = metadata.genres.first {
            return "\(firstGenre) Selection"
        }
        
        return "Picked for you"
    }
}

struct HomeHeroCardPlaceholder: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.secondary.opacity(colorScheme == .dark ? 0.2 : 0.15))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                }
            
            HStack(spacing: 24) {
                // Vertical Poster Skeleton
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 140, height: 210)
                
                // Details Skeleton
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 200, height: 24)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(width: 120, height: 16)
                    
                    Spacer()
                }
                .padding(.vertical, 30)
                
                Spacer()
            }
            .padding(24)
        }
        .frame(width: 500, height: 280)
        .skeletonPulse()
    }
}
