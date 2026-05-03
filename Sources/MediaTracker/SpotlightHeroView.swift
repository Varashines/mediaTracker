import SwiftUI
import SwiftData

struct SpotlightHeroView: View {
    let metadata: MediaThumbnailMetadata
    let onSelect: (MediaThumbnailMetadata) -> Void
    var isFastScrolling: Bool = false
    
    @Environment(\.modelContext) private var modelContext
    @State private var isHovered = false
    @State private var item: MediaItem?
    
    var body: some View {
        Button {
            onSelect(metadata)
        } label: {
            ZStack(alignment: .bottomLeading) {
                // 1. Immersive Backdrop
                if let backdrop = metadata.backdropURL, let url = URL(string: backdrop) {
                    CachedImage(url: url, targetSize: .backdropLarge, isFastScrolling: isFastScrolling) { _ in } placeholder: {
                        Rectangle().fill(Color.secondary.opacity(0.1))
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 400)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                } else {
                    Rectangle()
                        .fill(themeColor.gradient)
                        .frame(height: 400)
                }

                // 2. Content Overlay
                HStack(alignment: .bottom, spacing: 30) {
                    // Floating Poster
                    if let poster = metadata.posterURL, let url = URL(string: poster) {
                        CachedImage(url: url, targetSize: .thumbMedium, isFastScrolling: isFastScrolling) { _ in } placeholder: {
                            Rectangle().fill(Color.secondary.opacity(0.1))
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.yellow)
                            Text("CONTINUE WATCHING")
                                .font(.system(size: 10, weight: .black))
                                .kerning(2)
                                .foregroundStyle(.secondary)
                        }

                        Text(metadata.title)
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        if let info = metadata.nextEpisodeToWatchLabel ?? metadata.watchProgress {
                            Text(info)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.8))
                        }

                        HStack(spacing: 15) {
                            Button {
                                onSelect(metadata)
                            } label: {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Resume")
                                }
                                .font(.headline.bold())
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.white)
                                .foregroundStyle(.black)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Button {
                                onSelect(metadata)
                            } label: {
                                Text("Details")
                                    .font(.headline.bold())
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(.ultraThinMaterial)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 10)
                    }
                    .padding(.bottom, 40)
                    
                    Spacer()
                }
                .padding(.horizontal, 40)
            }
        }
        .buttonStyle(.plain)
        .frame(height: 400)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: 20)
        .padding(.horizontal, 30)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var themeColor: Color {
        metadata.themeColorHex.flatMap { Color(hex: $0) } ?? .blue
    }
}
