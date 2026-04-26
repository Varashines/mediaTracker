import SwiftData
import SwiftUI

private enum TVTrackingConstants {
    static let cornerRadius: CGFloat = 10
    static let cardCornerRadius: CGFloat = 12
    static let strokeWidth: CGFloat = 2.0
    static let secondaryStrokeWidth: CGFloat = 1.5
    static let animationDuration: Double = 1.2
}

extension Color {
    /// Returns a Color that linearly interpolates from pure blue (progress=0) to pure green (progress=1).
    static func blueToGreen(progress: Double) -> Color {
        let p = min(max(progress, 0), 1)
        return Color(red: 0.0, green: p, blue: 1.0 - p)
    }
}

struct TVTrackingView: View {
    @Bindable var tvDetails: TVShowDetails
    var themeColor: Color
    var onWatchedToggle: () -> Void
    var onSeasonSelected: ((TVSeason) -> Void)? = nil

    @State private var selectedSeasonNumber: Int?

    private var sortedSeasons: [TVSeason] {
        tvDetails.seasons.sorted(by: { $0.seasonNumber < $1.seasonNumber })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            if tvDetails.seasons.isEmpty {
                ContentUnavailableView(
                    "No season data", systemImage: "tv.slash",
                    description: Text("Season information hasn't been loaded yet.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                // Horizontal Season Selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(sortedSeasons, id: \.seasonNumber) { season in
                            SeasonTab(
                                season: season,
                                isSelected: selectedSeasonNumber == season.seasonNumber,
                                themeColor: themeColor
                            ) {
                                withAnimation(.spring(duration: 0.3)) {
                                    selectedSeasonNumber = season.seasonNumber
                                }
                                onSeasonSelected?(season)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }

                // Focused Episode Grid
                if let selectedNumber = selectedSeasonNumber,
                    let selectedSeason = tvDetails.seasons.first(where: {
                        $0.seasonNumber == selectedNumber
                    })
                {
                    SeasonSection(
                        season: selectedSeason, themeColor: themeColor,
                        onWatchedToggle: onWatchedToggle
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .onAppear {
            if selectedSeasonNumber == nil {
                selectInitialSeason()
            }
        }
    }

    private func selectInitialSeason() {
        // 1. Find the first season with unwatched episodes
        if let firstUnwatched = sortedSeasons.first(where: { season in
            season.episodes.contains(where: { !$0.isWatched })
        }) {
            selectedSeasonNumber = firstUnwatched.seasonNumber
            onSeasonSelected?(firstUnwatched)
        } else if let last = sortedSeasons.last {
            // 2. Default to the last season if all are watched
            selectedSeasonNumber = last.seasonNumber
            onSeasonSelected?(last)
        }
    }
}

private struct SeasonTab: View {
    let season: TVSeason
    let isSelected: Bool
    let themeColor: Color
    let action: () -> Void

    @Environment(\.colorScheme) var colorScheme

    private var progress: Double {
        let total = season.episodes.count
        guard total > 0 else { return 0 }
        let watched = season.episodes.filter { $0.isWatched }.count
        return Double(watched) / Double(total)
    }

    private var isFullyWatched: Bool {
        progress >= 1.0
    }

    private var isOngoing: Bool {
        progress > 0 && progress < 1.0
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Season \(season.seasonNumber)")
                if isFullyWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                }
            }
            .font(.system(.subheadline, weight: isSelected ? .bold : .medium))
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
            .foregroundStyle(.primary)
            .background {
                if isSelected {
                    Capsule()
                        .fill(themeColor.opacity(colorScheme == .dark ? 0.3 : 0.15))
                }
            }
            .liquidGlassPill(
                accentColor: isSelected ? themeColor : (isFullyWatched ? Color.semanticGreen(for: colorScheme) : .primary.opacity(0.12)),
                isSolid: false // Keep it glass!
            )
            .overlay {
                // Persistent Green Border for Completed Seasons (Selected or Not)
                if isFullyWatched {
                    Capsule()
                        .stroke(Color.semanticGreen(for: colorScheme).opacity(0.8), lineWidth: 1.5)
                        .padding(0.5)
                }
            }
            .overlay(
                progressOverlay
                    .padding(0.5) // Align with border
            )
            .scaleEffect(isSelected ? 1.05 : 1.0) // Proportional stretch on selection
            .shadow(
                color: isSelected ? themeColor.opacity(0.2) : .black.opacity(0.03),
                radius: isSelected ? 4 : 2, x: 0, y: 2)
        }
        .buttonStyle(.interactive(feedback: nil))
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: progress)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }

    private var borderColor: Color {
        if isSelected { return isFullyWatched ? themeColor : .indigo }
        if isFullyWatched { return Color.semanticGreen(for: colorScheme).opacity(0.8) }
        return Color.primary.opacity(0.08)  // Neutral base track
    }

    @ViewBuilder
    private var progressOverlay: some View {
        if isOngoing {
            Capsule()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.semanticGreen(for: colorScheme),
                    lineWidth: TVTrackingConstants.strokeWidth + 0.5) // Slightly thicker to be visible
        }
    }
}

private struct SeasonSection: View {
    @Bindable var season: TVSeason
    var themeColor: Color
    var onWatchedToggle: () -> Void
    @Environment(\.colorScheme) var colorScheme

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)
    ]

    private var isAllWatched: Bool {
        !season.episodes.isEmpty && season.episodes.allSatisfy { $0.isWatched }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Season \(season.seasonNumber)")
                            .font(.headline)
                        if let date = season.airDate, let parsed = DateUtils.parseDate(date) {
                            Text("(\(parsed.formatted(.dateTime.year())))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if season.episodeCount > 0 {
                        Text("\(season.episodeCount) episodes")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Button {
                    toggleSeasonWatchedStatus()
                } label: {
                    Label(
                        isAllWatched ? "Clear Season" : "Mark Season Watched",
                        systemImage: isAllWatched ? "xmark.circle" : "checkmark.circle"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(isAllWatched ? .secondary : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        if isAllWatched {
                            Color.secondary.opacity(0.1)
                        } else {
                            themeColor.opacity(colorScheme == .dark ? 0.35 : 0.15)
                                .background(.ultraThinMaterial)
                        }
                    }
                    .clipShape(Capsule())
                    .overlay {
                        if !isAllWatched {
                            Capsule()
                                .stroke(
                                    themeColor.opacity(colorScheme == .dark ? 0.5 : 0.3),
                                    lineWidth: 0.5)
                        }
                    }
                }
                .buttonStyle(.interactive(feedback: nil))
                .disabled(season.episodes.isEmpty)
            }

            if season.episodes.isEmpty {
                ContentUnavailableView(
                    "No episodes", systemImage: "sparkles.tv",
                    description: Text("Episode data is not available for this season.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(
                        season.episodes.sorted(by: { $0.episodeNumber < $1.episodeNumber }),
                        id: \.episodeNumber
                    ) { ep in
                        EpisodeCube(episode: ep, themeColor: themeColor) {
                            onWatchedToggle()
                        }
                    }
                }
            }
        }
    }

    private func toggleSeasonWatchedStatus() {
        withAnimation {
            let targetStatus = !isAllWatched
            for episode in season.episodes {
                episode.isWatched = targetStatus
            }
            season.tvShowDetails?.recalculateCachedProperties(triggerSync: true)
            onWatchedToggle()
        }
    }
}

private struct EpisodeCube: View {
    @Bindable var episode: TVEpisode
    var themeColor: Color
    var onToggle: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.2)) {
                episode.isWatched.toggle()
                FeedbackManager.shared.trigger(episode.isWatched ? .markWatched : .unmarkWatched)
                episode.season?.tvShowDetails?.recalculateCachedProperties(triggerSync: true)
                onToggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text("E\(episode.episodeNumber)")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .liquidGlassPill(
                            accentColor: badgeStrokeColor,
                            isSolid: episode.isWatched,
                            foregroundColor: badgeForegroundColor
                        )

                    Spacer()

                    if episode.isWatched {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.semanticGreen(for: colorScheme))
                            .font(.caption)
                    }
                }

                Text(episode.name.isEmpty ? "TBA" : episode.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 36, alignment: .topLeading)

                Spacer(minLength: 4)

                HStack {
                    if let date = episode.airDateAsDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let runtime = episode.runtime, runtime > 0 {
                        Text("\(runtime)m")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(
                RoundedRectangle(cornerRadius: TVTrackingConstants.cardCornerRadius)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: TVTrackingConstants.cardCornerRadius)
                            .stroke(
                                episode.isWatched
                                    ? Color.green.opacity(0.3) : Color.primary.opacity(0.05),
                                lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.interactive(feedback: nil))
    }

    private var badgeForegroundColor: Color {
        if episode.isWatched { return .white }
        return .secondary
    }

    private var badgeBackgroundColor: Color {
        if episode.isWatched {
            return Color.semanticGreen(for: colorScheme)
        } else {
            return Color.secondary.opacity(0.12)
        }
    }

    private var badgeStrokeColor: Color {
        if episode.isWatched {
            return Color.semanticGreen(for: colorScheme)
        } else {
            return Color.primary.opacity(0.08)
        }
    }
}

#if DEBUG
    #Preview {
        let details: TVShowDetails = {
            let d = TVShowDetails(tmdbID: 0)
            let season1 = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 2, airDate: nil)
            let ep1 = TVEpisode(
                episodeNumber: 1, seasonNumber: 1, name: "Pilot", overview: "", airDate: nil,
                runtime: 42)
            let ep2 = TVEpisode(
                episodeNumber: 2, seasonNumber: 1, name: "Second", overview: "", airDate: nil,
                runtime: 44)
            ep1.season = season1
            ep2.season = season1
            season1.episodes = [ep1, ep2]
            d.seasons = [season1]
            return d
        }()

        return TVTrackingView(tvDetails: details, themeColor: .accentColor) {}
            .padding()
    }
#endif
