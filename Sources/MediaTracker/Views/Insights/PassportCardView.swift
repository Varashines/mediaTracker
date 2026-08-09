import SwiftUI
import AppKit

struct PassportCardView: View {
    let stats: LibraryStats
    @Environment(\.colorScheme) var colorScheme

    private var personalityColor: Color {
        switch stats.ratingPersonality {
        case "Hopeless Romantic": return Color(red: 1.0, green: 0.35, blue: 0.60)
        case "Harsh Critic":      return Color(red: 1.0, green: 0.30, blue: 0.30)
        case "Enthusiast":        return Color(red: 1.0, green: 0.55, blue: 0.15)
        case "Mystery Critic":    return Color(red: 0.70, green: 0.70, blue: 0.85)
        default:                  return Color(red: 1.0, green: 0.78, blue: 0.15)
        }
    }

    var body: some View {
        ZStack {
            // Dark Velvet Backdrop
            Color(white: 0.04)

            // Accent Radial Glow Top-Right
            RadialGradient(
                colors: [
                    personalityColor.opacity(0.28),
                    personalityColor.opacity(0.08),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 360
            )

            VStack(spacing: 24) {
                // Header: Spotify Wrapped Title & MediaTracker Logo Badge
                HStack(alignment: .center) {
                    HStack(spacing: 10) {
                        // MediaTracker Logo App Icon Badge
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [personalityColor, personalityColor.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 36, height: 36)
                                .shadow(color: personalityColor.opacity(0.5), radius: 6, y: 2)

                            Image(systemName: "popcorn.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("MEDIATRACKER")
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .kerning(2.0)
                                .foregroundStyle(.white)
                            Text("CINEMA WRAPPED")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(personalityColor)
                        }
                    }

                    Spacer()
                }

                // Badges Row: Archetype + Taste Affinity
                HStack(spacing: 8) {
                    if !stats.archetype.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: archetypeIcon(stats.archetype))
                                .font(.system(size: 10, weight: .bold))
                            Text(stats.archetype.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .kerning(1.2)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(personalityColor)
                        )
                        .shadow(color: personalityColor.opacity(0.4), radius: 8, y: 3)
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(stats.ratingPersonality.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .kerning(1.2)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(white: 0.15))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                    )

                    Spacer()
                }

                // Wrapped Metrics Grid
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        wrappedStatCard(
                            title: "TOTAL MEDIA",
                            value: "\(stats.totalMovies + stats.totalTVShows)",
                            subtitle: "\(stats.totalMovies) Movies · \(stats.totalTVShows) TV",
                            icon: "film.stack"
                        )

                        wrappedStatCard(
                            title: "TIME WATCHED",
                            value: stats.totalWatchTimeHuman,
                            subtitle: "\(stats.totalEpisodesWatched) Episodes",
                            icon: "clock.fill"
                        )
                    }

                    HStack(spacing: 12) {
                        wrappedStatCard(
                            title: "TOP GENRE",
                            value: stats.topGenre ?? "Exploring",
                            subtitle: stats.topGenre != nil
                                ? (stats.genreDNA.first.map { "\(Int(round($0.percentage)))%" } ?? "10+ titles")
                                : "Min. 10 titles in genre",
                            icon: "sparkles"
                        )

                        wrappedStatCard(
                            title: "TOP ACTOR",
                            value: stats.topRatedActors.first?.name ?? "N/A",
                            subtitle: stats.topRatedActors.first.map { "\($0.count) titles" } ?? "",
                            icon: "star.fill"
                        )
                    }
                }

                // Cinema DNA Barcode Spectrum
                if !stats.barcodeData.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("CINEMA DNA SIGNATURE")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .kerning(2)
                                .foregroundStyle(personalityColor)

                            Spacer()

                            Text("\(stats.barcodeData.count) TITLES")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.6))
                        }

                        HStack(spacing: 1.5) {
                            ForEach(stats.barcodeData.prefix(120)) { slice in
                                RoundedRectangle(cornerRadius: 0.5)
                                    .fill(tasteColor(slice.tasteValue))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 32)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(white: 0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )

                    HStack(spacing: 12) {
                        wrappedStatCard(
                            title: "COMPLETED",
                            value: "\(stats.completedMovies + stats.completedTVShows)",
                            subtitle: "\(stats.completedMovies) Movies · \(stats.completedTVShows) TV",
                            icon: "checkmark.circle.fill"
                        )

                        wrappedStatCard(
                            title: "TOP CREATOR",
                            value: stats.topRatedCreators.first?.name ?? "N/A",
                            subtitle: stats.topRatedCreators.first.map { "\($0.count) titles" } ?? "",
                            icon: "pencil.and.outline"
                        )
                    }
                }

                Spacer(minLength: 0)

                // Spotify Wrapped Footer Branding
                HStack {
                    Text("TRACKED WITH MEDIATRACKER")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    if let memberSince = stats.memberSince {
                        Text(memberSince.formatted(.dateTime.year()))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(personalityColor)
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 420, height: 630)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(personalityColor.opacity(0.4), lineWidth: 1.2)
        )
    }

    private func wrappedStatCard(title: String, value: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(personalityColor)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
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
        case "Love": return Color(red: 1.0, green: 0.40, blue: 0.70)
        case "Like": return Color(red: 0.30, green: 0.85, blue: 0.50)
        case "Dislike": return Color(red: 1.0, green: 0.35, blue: 0.35)
        default: return Color(white: 0.45)
        }
    }

    // Render high-resolution uncropped 3x Retina NSImage using SwiftUI ImageRenderer
    @MainActor
    func renderToImage() -> NSImage? {
        let exportCanvas = ZStack {
            Color(white: 0.04)

            self
                .frame(width: 420, height: 630)
                .padding(24)
        }
        .frame(width: 468, height: 678)
        .environment(\.colorScheme, .dark)

        return exportCanvas.renderToNSImage(width: 468, height: 678)
    }
}

extension LibraryStats {
    var totalWatchTimeHuman: String {
        let totalHours = totalWatchTimeMinutes / 60
        let days = totalHours / 24
        let hours = totalHours % 24
        if days > 0 {
            return "\(pluralizedDaysLabel(days)) \(pluralizedHoursLabel(hours))"
        } else if hours > 0 {
            return pluralizedHoursLabel(hours)
        }
        return "\(totalWatchTimeMinutes)m"
    }
}
