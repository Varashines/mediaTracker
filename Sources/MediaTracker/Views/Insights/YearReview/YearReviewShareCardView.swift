import SwiftUI
import SwiftData
import AppKit

// MARK: - Year Review Share Card

struct YearReviewShareCardView: View {
    let review: YearInReview
    var selectedFavorites: [YearWatchedTitle] = []

    static let cardSize = CGSize(width: 440, height: 720)

    private var hoursWatched: Double {
        Double(review.totalMinutes) / 60.0
    }

    private var formattedHours: String {
        if hoursWatched >= 100 {
            return "\(Int(hoursWatched.rounded()))h"
        } else {
            return String(format: "%.1fh", hoursWatched)
        }
    }

    private var primaryAccent: Color {
        Color(red: 0.55, green: 0.35, blue: 0.95)
    }

    private var secondaryAccent: Color {
        Color(red: 0.15, green: 0.75, blue: 0.95)
    }

    private var busiestDayString: String? {
        guard let busiest = review.busiestDay else { return nil }
        let hours = Double(busiest.minutes) / 60.0
        let dur = hours >= 1.0 ? String(format: "%.1fh", hours) : "\(busiest.minutes)m"
        let dateStr = busiest.day.formatted(.dateTime.month(.abbreviated).day())
        return "\(dateStr) · \(dur)"
    }

    var body: some View {
        VStack(spacing: 16) {
            headerBar

            heroWatchTimeSection

            statPillsRow

            insightsDNASurface

            if !selectedFavorites.isEmpty {
                favoritesSection
            }

            Spacer(minLength: 0)

            footerBar
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .background(backgroundMesh)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            primaryAccent.opacity(0.8),
                            Color.white.opacity(0.35),
                            secondaryAccent.opacity(0.6),
                            Color.white.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Background Mesh

    private var backgroundMesh: some View {
        ZStack {
            Color(white: 0.03)

            RadialGradient(
                colors: [primaryAccent.opacity(0.55), Color(white: 0.03)],
                center: .topLeading,
                startRadius: 10,
                endRadius: 420
            )

            RadialGradient(
                colors: [secondaryAccent.opacity(0.35), Color.clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 360
            )

            RadialGradient(
                colors: [Color(red: 0.95, green: 0.35, blue: 0.55).opacity(0.22), Color.clear],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 350
            )
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .center) {
            HStack(spacing: 9) {
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: primaryAccent.opacity(0.4), radius: 4, y: 2)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(primaryAccent.opacity(0.3))
                            .frame(width: 24, height: 24)
                        Image(systemName: "film.stack.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                Text("MEDIATRACKER")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .kerning(1.8)
                    .foregroundStyle(.white.opacity(0.95))
            }

            Spacer()

            Text("\(String(review.year)) WRAPPED")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(primaryAccent.opacity(0.4))
                        .overlay(Capsule().stroke(primaryAccent.opacity(0.8), lineWidth: 1))
                )
        }
    }

    // MARK: - Hero Watch Time

    private var heroWatchTimeSection: some View {
        VStack(spacing: 4) {
            Text("TOTAL WATCH TIME")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(1.8)
                .foregroundStyle(secondaryAccent)

            Text(formattedHours)
                .font(.system(size: 48, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color.white.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: primaryAccent.opacity(0.5), radius: 16, y: 4)

            if let busiest = busiestDayString {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.2))
                    Text("Busiest: \(busiest)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Stat Pills Row

    private var statPillsRow: some View {
        HStack(spacing: 8) {
            glassStatPill(
                title: "\(review.totalEpisodes.formatted())",
                subtitle: "\(review.totalSeries) Series",
                icon: "tv.fill",
                accent: primaryAccent
            )

            glassStatPill(
                title: "\(review.totalMovies)",
                subtitle: "Movies",
                icon: "film.fill",
                accent: secondaryAccent
            )

            glassStatPill(
                title: "\(review.totalDaysWatched)",
                subtitle: "Active Days",
                icon: "calendar",
                accent: Color(red: 0.95, green: 0.45, blue: 0.65)
            )
        }
    }

    private func glassStatPill(title: String, subtitle: String, icon: String, accent: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text(subtitle.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    // MARK: - Insights & DNA Surface

    private var insightsDNASurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top Networks / Studios
            if !review.topNetworks.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("TOP STUDIOS & NETWORKS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .kerning(1.2)
                            .foregroundStyle(secondaryAccent)
                        Spacer()
                    }

                    HStack(spacing: 6) {
                        ForEach(Array(review.topNetworks.prefix(3)), id: \.name) { net in
                            HStack(spacing: 4) {
                                Text(net.name)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                Text("\(net.count)")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.8))
                            )
                        }
                    }
                }
            }

            // Top Genres
            if !review.topGenres.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("GENRE DNA")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .kerning(1.2)
                            .foregroundStyle(primaryAccent.opacity(0.9))
                        Spacer()
                    }

                    HStack(spacing: 6) {
                        ForEach(Array(review.topGenres.prefix(3)), id: \.name) { genre in
                            Text(genre.name)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(primaryAccent.opacity(0.2))
                                        .overlay(Capsule().stroke(primaryAccent.opacity(0.4), lineWidth: 0.8))
                                )
                        }
                    }
                }
            }

            // Top Talent
            if let topActor = review.topActors.first {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.2))
                    Text("Top Talent:")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(topActor.name)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if topActor.count > 1 {
                        Text("(\(topActor.count) titles)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Selected Favorites Ribbon

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FAVORITE PICKS OF \(String(review.year))")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .kerning(1.2)
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                Image(systemName: "heart.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.55))
            }

            HStack(spacing: 8) {
                ForEach(selectedFavorites.prefix(3)) { item in
                    favoriteTitleCard(item)
                }
            }
        }
    }

    private func favoriteTitleCard(_ item: YearWatchedTitle) -> some View {
        HStack(spacing: 8) {
            if let posterURL = item.posterURL.flatMap(URL.init) {
                CachedImage(url: posterURL, targetSize: .thumbSmall) { _ in } placeholder: {
                    Rectangle().fill(Color.white.opacity(0.1))
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 32, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 32, height: 48)
                    Image(systemName: item.type == .tvShow ? "tv" : "film")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(item.type == .tvShow ? "TV Series" : "Movie")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(secondaryAccent)
            }

            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            Text("100% OFFLINE & PRIVATE")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .kerning(1.2)
                .foregroundStyle(.white.opacity(0.45))

            Spacer()

            Text("TRACKED WITH MEDIATRACKER")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .kerning(1.2)
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    @MainActor
    func renderToImage() -> NSImage? {
        renderToNSImage(width: Self.cardSize.width, height: Self.cardSize.height, scale: 3.0)
    }
}
