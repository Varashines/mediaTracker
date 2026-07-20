import SwiftUI
import AppKit

struct PassportCardView: View {
    let stats: LibraryStats
    @Environment(\.colorScheme) var colorScheme

    private var personalityColor: Color {
        switch stats.ratingPersonality {
        case "Hopeless Romantic": return .pink
        case "Harsh Critic":      return .red
        case "Enthusiast":        return .orange
        case "Mystery Critic":    return .gray
        default:                  return .yellow
        }
    }

    private var cardGradient: LinearGradient {
        let base = personalityColor
        let isDark = colorScheme == .dark
        if isDark {
            return LinearGradient(
                colors: [base.opacity(0.18), Color(white: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [base.opacity(0.12), Color(white: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(alignment: .top) {
                Spacer(minLength: 24)
                VStack(spacing: 6) {
                    Image(systemName: "popcorn.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(personalityColor.opacity(0.7))
                    Text("CINEMA PASSPORT")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .kerning(4)
                        .foregroundStyle(personalityColor)
                }
                .padding(.leading, stats.currentStreak > 0 ? 50 : 0)
                
                Spacer()
                
                if stats.currentStreak > 0 {
                    Text("🔥 \(stats.currentStreak)d streak")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.orange.opacity(0.12)))
                }
            }

            // Archetype + Member Since
            VStack(spacing: 4) {
                if !stats.archetype.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: archetypeIcon(stats.archetype))
                            .font(.system(size: 10))
                        Text(stats.archetype.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(1.5)
                    }
                    .foregroundStyle(personalityColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(personalityColor.opacity(0.12)))
                }
                if let memberSince = stats.memberSince {
                    Text("Member since \(memberSince.formatted(.dateTime.year()))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .padding(.horizontal, 40)

            // Stats row
            HStack(spacing: 0) {
                statBlock(value: "\(stats.totalMovies + stats.totalTVShows)", label: "Titles")
                Divider().frame(height: 30)
                statBlock(value: stats.totalWatchTimeHuman, label: "Watched")
                Divider().frame(height: 30)
                statBlock(value: "\(stats.totalEpisodesWatched)", label: "Episodes")
            }
            .padding(.horizontal, 20)

            // Taste + Genres
            HStack(alignment: .top, spacing: 24) {
                // Mini taste donut
                tasteDonutView
                    .frame(width: 80, height: 80)

                // Top genres
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOP GENRES")
                        .font(.system(size: 8, weight: .semibold))
                        .kerning(1.5)
                        .foregroundStyle(.tertiary)
                    ForEach(stats.genreDNA.prefix(3), id: \.name) { genre in
                        HStack(spacing: 4) {
                            Text(genre.name)
                                .font(.system(size: 10))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(Int(genre.percentage))%")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)

            // Spectrum barcode
            if !stats.barcodeData.isEmpty {
                VStack(spacing: 6) {
                    Text("CINEMA DNA SIGNATURE")
                        .font(.system(size: 8, weight: .semibold))
                        .kerning(2)
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 1) {
                        ForEach(stats.barcodeData.prefix(120)) { slice in
                            RoundedRectangle(cornerRadius: 0.5)
                                .fill(tasteColor(slice.tasteValue))
                                .frame(width: 2.5)
                        }
                    }
                    .frame(height: 24)
                }
                .padding(.horizontal, 20)
            }

            Spacer(minLength: 0)

            // Footer
            Text("Made with MediaTracker")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .frame(width: 400, height: 550)
        .background(cardGradient)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(personalityColor.opacity(0.15), lineWidth: 0.8)
        )
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var tasteDonutView: some View {
        let total = Double(max(stats.lovedCount + stats.likedCount + stats.dislikedCount + stats.unratedCount, 1))
        let loved = Double(stats.lovedCount) / total
        let liked = Double(stats.likedCount) / total
        let disliked = Double(stats.dislikedCount) / total
        let unrated = Double(stats.unratedCount) / total

        return Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 4
            var startAngle = -90.0

            for (pct, color) in [(loved, Color.pink), (liked, Color.green), (disliked, Color.red.opacity(0.7)), (unrated, Color.gray.opacity(0.5))] {
                if pct > 0 {
                    let endAngle = startAngle + pct * 360
                    var path = Path()
                    path.move(to: center)
                    path.addArc(center: center, radius: radius,
                                startAngle: .degrees(startAngle), endAngle: .degrees(endAngle), clockwise: false)
                    path.closeSubpath()
                    context.fill(path, with: .color(color))
                    startAngle = endAngle
                }
            }

            // Center hole matching gradient color approximation
            context.fill(Circle().path(in: CGRect(x: center.x - 14, y: center.y - 14, width: 28, height: 28)),
                        with: .color(colorScheme == .dark ? Color(white: 0.10) : Color(white: 0.98)))
        }
    }

    private func archetypeIcon(_ archetype: String) -> String {
        if archetype.contains("Connoisseur") { return "checkmark.seal.fill" }
        if archetype.contains("Newcomer") { return "leaf.fill" }
        if archetype.contains("Binger") || archetype.contains("Streamer") { return "play.rectangle.fill" }
        if archetype.contains("Completionist") { return "checklist" }
        if archetype.contains("Explorer") { return "binoculars.fill" }
        if archetype.contains("Collector") { return "square.stack.3d.up.fill" }
        if archetype.contains("Critic") { return "magnifyingglass" }
        return "sparkles"
    }

    private func tasteColor(_ value: String) -> Color {
        switch value {
        case "Love": return Color.pink.opacity(0.85)
        case "Like": return Color.green.opacity(0.85)
        case "Dislike": return Color.red.opacity(0.65)
        default: return Color.gray.opacity(0.4)
        }
    }

    // Render to NSImage
    func renderToImage() -> NSImage? {
        let renderView = self.environment(\.colorScheme, colorScheme)
        let controller = NSHostingController(rootView: renderView)
        let targetSize = CGSize(width: 400, height: 550)
        controller.view.frame = CGRect(origin: .zero, size: targetSize)

        let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds)!
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)

        let image = NSImage(size: targetSize)
        image.addRepresentation(bitmap)
        return image
    }
}

extension LibraryStats {
    var totalWatchTimeHuman: String {
        let hours = totalWatchTimeMinutes / 60
        let minutes = totalWatchTimeMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
