import SwiftUI

struct MediaShareCardView: View {
    let item: MediaItem
    var customCast: [SimpleCastMember]? = nil

    private var themeColor: Color {
        if let hex = item.themeColorHex {
            let cleanHex = hex.contains("|") ? String(hex.split(separator: "|")[0]) : hex
            if let color = Color(hex: cleanHex) {
                return color
            }
        }
        if let networkName = item.cachedNetwork {
            let first = networkName.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? networkName
            if let netColor = NetworkThemeManager.shared.color(for: first) {
                return netColor
            }
        }
        return Color(red: 0.25, green: 0.45, blue: 0.65)
    }

    private var releaseYearString: String? {
        guard let date = item.releaseDate else { return nil }
        let year = Calendar.current.component(.year, from: date)
        return year > 0 ? "\(year)" : nil
    }

    private var networkNameString: String? {
        guard let net = item.cachedNetwork else { return nil }
        return net.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
    }

    private var seasonsCountString: String? {
        guard let tv = item.tvShowDetails else { return nil }
        let count = (tv.numberOfSeasons ?? 0) > 0 ? (tv.numberOfSeasons ?? 0) : tv.seasons.count
        return count > 0 ? "\(count) SEASON\(count == 1 ? "" : "S")" : nil
    }

    private var episodesCountString: String? {
        guard let tv = item.tvShowDetails else { return nil }
        let count = tv.totalEpisodesCount > 0
            ? tv.totalEpisodesCount
            : (tv.numberOfEpisodes ?? tv.seasons.reduce(0) { $0 + max($1.episodeCount, $1.episodes.count) })
        return count > 0 ? "\(count) EPISODE\(count == 1 ? "" : "S")" : nil
    }

    private var isTV: Bool { item.type == .tvShow }
    private var placeholderIcon: String { isTV ? "tv.fill" : "film.fill" }
    private var creditLabel: String { isTV ? "CREATED BY" : "DIR." }

    var body: some View {
        VStack(spacing: 16) {
            headerBar
            posterSection
            infoSection
            tasteAndMoodSection
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 24)
        .frame(width: 440, height: 630)
        .background {
            ZStack {
                Color(white: 0.04)
                RadialGradient(
                    colors: [themeColor.opacity(0.52), themeColor.opacity(0.18), Color(white: 0.04)],
                    center: .top,
                    startRadius: 10,
                    endRadius: 520
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [themeColor.opacity(0.55), themeColor.opacity(0.2), Color.white.opacity(0.12)],
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
        .frame(width: 240, height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: themeColor.opacity(0.45), radius: 24, x: 0, y: 12)
        .shadow(color: .black.opacity(0.6), radius: 12, x: 0, y: 6)
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
        VStack(spacing: 6) {
            Text(item.title)
                .font(.system(size: item.title.count > 24 ? 16.5 : 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                if let creator = item.cachedCreators.first {
                    HStack(spacing: 3) {
                        Text(creditLabel)
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(themeColor)
                        Text(creator)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }

                if item.cachedCreators.first != nil && !item.displayCast.isEmpty {
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }

                let topCast = customCast ?? Array(item.displayCast.prefix(3))
                if !topCast.isEmpty {
                    Text(topCast.map(\.name).joined(separator: ", "))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
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

    // MARK: - Taste & Mood

    @ViewBuilder
    private var tasteAndMoodSection: some View {
        let hasTaste = item.taste != nil && item.taste != TasteValue.none
        let hasMood = item.mood != nil

        if hasTaste || hasMood {
            HStack(spacing: 10) {
                if let taste = item.taste, taste != TasteValue.none {
                    HStack(spacing: 5) {
                        Text(taste.emoji).font(.system(size: 11))
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
                        Text(mood.emojiChar).font(.system(size: 11))
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
        renderToNSImage(width: 440, height: 630)
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
