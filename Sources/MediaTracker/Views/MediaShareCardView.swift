import SwiftUI

struct MediaShareCardView: View {
    let item: MediaItem
    var customCast: [SimpleCastMember]? = nil

    private var themeColor: Color {
        if let hex = item.themeColorHex, let color = Color(themeHex: hex) {
            return color
        }
        if let networkName = item.cachedNetwork {
            let first = networkName.commaSeparatedValues.first ?? networkName
            if let netColor = NetworkThemeManager.shared.color(for: first) {
                return netColor
            }
        }
        return Color(red: 0.25, green: 0.45, blue: 0.65)
    }

    private var secondaryColor: Color {
        item.themeSecondaryColorHex.flatMap { Color(themeHex: $0) } ?? themeColor
    }

    private var mutedColor: Color {
        item.themeMutedColorHex.flatMap { Color(themeHex: $0) } ?? themeColor
    }

    private var releaseYearString: String? {
        guard let date = item.releaseDate else { return nil }
        let year = Calendar.current.component(.year, from: date)
        return year > 0 ? "\(year)" : nil
    }

    private var networkNameString: String? {
        guard let net = item.cachedNetwork else { return nil }
        return net.commaSeparatedValues.first
    }

    private var seasonsCountString: String? {
        guard let tv = item.tvShowDetails else { return nil }
        // Exclude Season 0 (Specials) from the fallback season count.
        let count = (tv.numberOfSeasons ?? 0) > 0
            ? (tv.numberOfSeasons ?? 0)
            : tv.seasons.liveModels.filter { $0.seasonNumber > 0 }.count
        return count > 0 ? "\(count) SEASON\(count == 1 ? "" : "S")" : nil
    }

    private var episodesCountString: String? {
        guard let tv = item.tvShowDetails else { return nil }
        // totalEpisodesCount and numberOfEpisodes already exclude Season 0;
        // the reduce fallback must also skip specials.
        let count = tv.totalEpisodesCount > 0
            ? tv.totalEpisodesCount
            : (tv.numberOfEpisodes ?? tv.seasons.liveModels
                .filter { $0.seasonNumber > 0 }
                .reduce(0) { $0 + max($1.episodeCount, $1.episodes.count) })
        return count > 0 ? "\(count) EPISODE\(count == 1 ? "" : "S")" : nil
    }

    private var isTV: Bool { item.type == .tvShow }
    private var placeholderIcon: String { isTV ? "tv.fill" : "film.fill" }
    private var creditLabel: String { isTV ? "CREATED BY" : "DIR." }

    var body: some View {
        VStack(spacing: 14) {
            headerBar
            posterSection
            infoSection
            tasteAndMoodSection
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(width: 400, height: 700)
        .background {
            ZStack {
                Color(white: 0.03)
                RadialGradient(
                    colors: [themeColor.opacity(0.68), mutedColor.opacity(0.35), Color(white: 0.03)],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: 540
                )
                RadialGradient(
                    colors: [secondaryColor.opacity(0.42), Color.clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 400
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            themeColor.opacity(0.80),
                            Color.white.opacity(0.40),
                            secondaryColor.opacity(0.60),
                            Color.white.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            HStack(spacing: 8) {
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: themeColor.opacity(0.4), radius: 4, x: 0, y: 2)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(themeColor.opacity(0.18))
                            .frame(width: 24, height: 24)
                        Image(systemName: placeholderIcon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(themeColor)
                    }
                }
                Text("MEDIATRACKER")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .kerning(1.8)
                    .foregroundStyle(.white.opacity(0.95))
            }

            Spacer()

            HStack(spacing: 6) {
                if isTV, let network = networkNameString {
                    Text(network.uppercased())
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(themeColor.opacity(0.35))
                                .overlay(Capsule().stroke(themeColor.opacity(0.6), lineWidth: 0.8))
                        )
                }
                if let yearStr = releaseYearString {
                    Text(yearStr)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isTV ? .white.opacity(0.12) : themeColor.opacity(0.35))
                                .overlay(Capsule().stroke(isTV ? .white.opacity(0.2) : themeColor.opacity(0.6), lineWidth: 0.8))
                        )
                }
            }
        }
    }

    // MARK: - Poster Section

    @ViewBuilder
    private var posterSection: some View {
        if isTV {
            posterWithSideSpecs
        } else {
            centeredPoster
        }
    }

    private var centeredPoster: some View {
        CachedImage(url: posterURL, targetSize: .thumbMedium) { _ in } placeholder: {
            posterPlaceholder
        }
        .aspectRatio(contentMode: .fill)
        .frame(width: 260, height: 390)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.40), themeColor.opacity(0.30), Color.white.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: themeColor.opacity(0.65), radius: 28, x: 0, y: 14)
        .shadow(color: .black.opacity(0.75), radius: 14, x: 0, y: 8)
    }

    private var posterWithSideSpecs: some View {
        HStack(spacing: 10) {
            if let seasonsStr = seasonsCountString {
                Text(seasonsStr)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .kerning(2.2)
                    .foregroundStyle(.white.opacity(0.75))
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
                    .frame(width: 22)
            } else {
                Spacer().frame(width: 22)
            }

            centeredPoster

            if let episodesStr = episodesCountString {
                Text(episodesStr)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .kerning(2.2)
                    .foregroundStyle(.white.opacity(0.75))
                    .rotationEffect(.degrees(90))
                    .fixedSize()
                    .frame(width: 22)
            } else {
                Spacer().frame(width: 22)
            }
        }
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(themeColor.opacity(0.15))
            .overlay(
                Image(systemName: placeholderIcon)
                    .font(.system(size: 40))
                    .foregroundStyle(themeColor.opacity(0.4))
            )
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(spacing: 7) {
            Text(item.title)
                .font(.system(size: item.title.count > 24 ? 16.5 : 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            if let creator = item.cachedCreators.first {
                HStack(spacing: 5) {
                    Text(creditLabel)
                        .font(.system(size: 8.5, weight: .black, design: .monospaced))
                        .kerning(0.6)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(brightAccent.opacity(0.20)))
                        .overlay(Capsule().stroke(brightAccent.opacity(0.55), lineWidth: 0.7))
                    Text(creator)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            let topCast = customCast ?? Array(item.displayCast.prefix(3))
            if !topCast.isEmpty {
                let castNames = topCast.map(\.name).joined(separator: ", ")
                Text(castNames)
                    .font(.system(size: castNames.count > 45 ? 10 : castNames.count > 30 ? 11 : 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
            }

            if !item.cachedGenres.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(item.cachedGenres.prefix(3)), id: \.self) { genre in
                        Text(genre.uppercased())
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background(Capsule().fill(.white.opacity(0.08)))
                            .overlay(
                                Capsule()
                                    .stroke(.white.opacity(0.15), lineWidth: 0.8)
                            )
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    /// Theme accent brightened for legibility on the card's dark background.
    private var brightAccent: Color {
        themeColor.highContrastAccent(colorScheme: .dark)
    }

    // MARK: - Taste & Mood

    @ViewBuilder
    private var tasteAndMoodSection: some View {
        let hasTaste = item.taste != nil && item.taste != TasteValue.none
        let hasMood = item.mood != nil

        if hasTaste || hasMood {
            HStack(spacing: 10) {
                if let taste = item.taste, taste != TasteValue.none {
                    HStack(spacing: 5) {
                        Image(systemName: taste.iconName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(taste.color)
                        Text(taste.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .kerning(1.1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(taste.color.opacity(0.35)))
                    .overlay(Capsule().stroke(taste.color.opacity(0.65), lineWidth: 1))
                    .shadow(color: taste.color.opacity(0.35), radius: 6, x: 0, y: 2)
                }

                if let moodRaw = item.mood, let mood = Mood(rawValue: moodRaw) {
                    HStack(spacing: 5) {
                        Image(systemName: mood.emoji)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(mood.color)
                        Text(mood.rawValue)
                            .font(.system(size: 10, weight: .bold))
                            .kerning(1.1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var posterURL: URL? {
        guard let posterURL = item.effectivePosterURL else { return nil }
        return URL(string: posterURL)
    }

    @MainActor
    func renderToImage() -> NSImage? {
        renderToNSImage(width: 400, height: 700)
    }
}

extension View {
    @MainActor
    func renderToNSImage(width: CGFloat, height: CGFloat, scale: CGFloat = 3.0) -> NSImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        return renderer.nsImage
    }
}
