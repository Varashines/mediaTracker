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
    private let posterWidth: CGFloat = 110
    private let posterHeight: CGFloat = 160
    private let posterCornerRadius: CGFloat = 12
    private let posterPadding: CGFloat = 16

    private var themeColor: Color {
        if let hex = metadata.themeColorHex, let color = Color(hex: hex) {
            return color
        }
        return .accentColor
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // 1. Background Layer (Backdrop with Glass)
            if let backdrop = metadata.backdropURL, let url = URL(string: backdrop) {
                CachedImage(url: url, targetSize: .backdropCompact, isFastScrolling: isFastScrolling) { _ in } placeholder: {
                    Rectangle().fill(Color.secondary.opacity(0.1))
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: cardWidth, height: cardHeight)
                .clipped()
                .overlay(Color.black.opacity(isHovered ? 0.4 : 0.45))
            } else {
                Rectangle().fill(Color.black.opacity(0.85))
                    .frame(width: cardWidth, height: cardHeight)
            }
            
            // 2. Matching Your Taste Tag (Top Right)
            if let context = recommendationContext {
                let accent = AppTheme.Colors.accent
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                                .font(AppTheme.Font.small)
                            Text(context.uppercased())
                                .font(AppTheme.Font.small)
                                .tracking(0.8)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .background {
                            Capsule()
                                .fill(accent.opacity(colorScheme == .dark ? 0.25 : 0.35))
                                .background(.thinMaterial)
                        }
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().stroke(accent.opacity(0.4), lineWidth: 0.8)
                        }
                        .shadow(color: AppTheme.Colors.shadowAmbient(for: colorScheme), radius: 6, y: 3)
                        .padding(12)
                    }
                    Spacer()
                }
            }
            
            HStack(spacing: 0) {
                // 3. Poster with padding, rounded corners, hover lift + glow
                if let poster = metadata.posterURL, let url = URL(string: poster) {
                    ZStack {
                        // Glow behind poster (visible on hover)
                        RoundedRectangle(cornerRadius: posterCornerRadius + 2, style: .continuous)
                            .fill(themeColor.opacity(isHovered ? 0.15 : 0))
                            .shadow(color: themeColor.opacity(isHovered ? 0.15 : 0), radius: isHovered ? 10 : 0, y: 0)
                            .frame(width: posterWidth + 4, height: posterHeight + 4)

                        // Poster image
                        CachedImage(url: url, targetSize: .thumbMedium, isFastScrolling: isFastScrolling) { _ in } placeholder: {
                            RoundedRectangle(cornerRadius: posterCornerRadius, style: .continuous)
                                .fill(Color.secondary.opacity(0.15))
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: posterWidth, height: posterHeight)
                        .clipShape(RoundedRectangle(cornerRadius: posterCornerRadius, style: .continuous))
                        .shadow(color: .black.opacity(isHovered ? 0.25 : 0.2), radius: isHovered ? 7 : 5, y: isHovered ? 3 : 2)
                    }
                    .padding(.leading, posterPadding)
                    .padding(.vertical, posterPadding)
                    .offset(y: isHovered ? -4 : 0)

                    // 4. Info Pane
                    VStack(alignment: .leading, spacing: 8) {
                        Text(metadata.title)
                            .font(AppTheme.Font.title3)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .shadow(radius: 2)
                        
                        Text(metadata.formattedMetadata)
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 20)
                    .padding(.vertical, 20)
                }
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                .stroke(Color.white.opacity(isHovered ? 0.2 : 0.08), lineWidth: 0.8)
        }
        .shadow(color: isHovered ? AppTheme.Colors.shadowElevated(for: colorScheme) : AppTheme.Colors.shadowAmbient(for: colorScheme), radius: 8, y: 4)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(AppTheme.Animation.springGentle, value: isHovered)
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
