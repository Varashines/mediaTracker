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
    var isRefreshing: Bool = false
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
                        isRefreshing: isRefreshing,
                        onWatchedToggle: onWatchedToggle,
                        onSeasonSelected: onSeasonSelected
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .onAppear {
                        autoFetchIfNeeded(season: selectedSeason)
                    }
                    .onChange(of: selectedNumber) { _, _ in
                        autoFetchIfNeeded(season: selectedSeason)
                    }
                }
            }
        }
        .onAppear {
            if selectedSeasonNumber == nil {
                selectInitialSeason()
            }
        }
        .onChange(of: tvDetails.seasons.count) { _, _ in
            if selectedSeasonNumber == nil {
                selectInitialSeason()
            }
        }
        .onChange(of: tvDetails.item?.lastUpdated) { _, _ in
            // If we are currently showing "No episodes" or nothing is selected,
            // re-run the selection logic because background data might have arrived.
            let currentSeason = tvDetails.seasons.first(where: {
                $0.seasonNumber == selectedSeasonNumber
            })
            if selectedSeasonNumber == nil || (currentSeason?.totalEpisodesCount == 0) {
                selectInitialSeason()
            }
        }
    }

    private func autoFetchIfNeeded(season: TVSeason) {
        if season.totalEpisodesCount == 0 && season.episodeCount > 0 && !isRefreshing {
            onSeasonSelected?(season)
        }
    }

    private func selectInitialSeason() {
        // 1. Prioritize non-zero seasons that have unwatched episodes
        let activeSeasons = sortedSeasons.filter { $0.seasonNumber > 0 }
        
        if let firstUnwatched = activeSeasons.first(where: { season in
            season.watchedEpisodesCount < season.totalEpisodesCount
        }) {
            selectedSeasonNumber = firstUnwatched.seasonNumber
            onSeasonSelected?(firstUnwatched)
            return
        }
        
        // 2. If all non-zero seasons are watched, pick the last non-zero season
        if let lastActive = activeSeasons.last {
            selectedSeasonNumber = lastActive.seasonNumber
            onSeasonSelected?(lastActive)
            return
        }
        
        // 3. Fallback to Specials (Season 0) only if it's the only one available
        if let specials = sortedSeasons.first(where: { $0.seasonNumber == 0 }) {
            selectedSeasonNumber = 0
            onSeasonSelected?(specials)
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
        let total = season.totalEpisodesCount
        guard total > 0 else { return 0 }
        let watched = season.watchedEpisodesCount
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
            let accent = themeColor.readableAccent(colorScheme: colorScheme)
            HStack(spacing: 8) {
                Text("Season \(season.seasonNumber)")

                if isFullyWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.semanticGreen(for: colorScheme))
                }
            }
            .font(.system(size: 13, weight: isSelected ? .black : .bold, design: .rounded))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(accent.opacity(colorScheme == .dark ? 0.3 : 0.15))
                } else {
                    Capsule()
                        .fill(Color.primary.opacity(0.05))
                }
            }
            .overlay {
                if isOngoing {
                    Capsule()
                        .trim(from: 0, to: progress)
                        .stroke(Color.semanticGreen(for: colorScheme), lineWidth: 2)
                } else if isFullyWatched {
                    Capsule()
                        .stroke(Color.semanticGreen(for: colorScheme).opacity(0.5), lineWidth: 1)
                } else if isSelected {
                    Capsule()
                        .stroke(accent.opacity(0.5), lineWidth: 1)
                }
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: isSelected)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: progress)
    }
}

private struct SeasonSection: View {
    @Bindable var season: TVSeason
    var themeColor: Color
    var isRefreshing: Bool = false
    var onWatchedToggle: () -> Void
    var onSeasonSelected: ((TVSeason) -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)
    ]

    private var isAllWatched: Bool {
        season.totalEpisodesCount > 0 && season.watchedEpisodesCount == season.totalEpisodesCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Season \(season.seasonNumber)")
                            .font(.system(size: 20, weight: .black, design: .rounded))

                        if let date = season.airDate, let parsed = DateUtils.parseDate(date) {
                            Text(parsed.formatted(.dateTime.year()))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if season.episodeCount > 0 {
                        Text("\(season.episodeCount) EPISODES")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.secondary)
                            .kerning(1)
                    }
                }

                Spacer()

                Button {
                    toggleSeasonWatchedStatus()
                } label: {
                    let accent = themeColor.readableAccent(colorScheme: colorScheme)
                    HStack(spacing: 6) {
                        Image(
                            systemName: isAllWatched
                                ? "arrow.counterclockwise" : "checkmark.seal.fill")
                        Text(isAllWatched ? "Reset" : "Mark All")
                    }
                    .font(.system(size: 11, weight: .black))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isAllWatched ? Color.primary.opacity(0.05) : accent.opacity(0.15))
                    .foregroundStyle(isAllWatched ? .secondary : accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(season.totalEpisodesCount == 0)
            }
            .padding(.horizontal, 4)

            if season.totalEpisodesCount == 0 {
                VStack(spacing: 20) {
                    ContentUnavailableView(
                        "No episodes loaded", systemImage: "sparkles.tv",
                        description: Text(season.episodeCount > 0 
                                          ? "This season has \(season.episodeCount) episodes according to metadata." 
                                          : "Episode data is not available for this season.")
                    )
                    
                    if season.episodeCount > 0 {
                        Button {
                            onSeasonSelected?(season)
                        } label: {
                            if isRefreshing {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Fetch Episodes", systemImage: "arrow.down.circle.fill")
                                    .font(.system(size: 13, weight: .bold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(themeColor)
                        .controlSize(.regular)
                        .disabled(isRefreshing)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(
                        season.episodes.sorted(by: { $0.episodeNumber < $1.episodeNumber }),
                        id: \.persistentModelID
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
        let targetStatus = !isAllWatched
        withAnimation {
            for episode in season.episodes {
                episode.isWatched = targetStatus
            }
            onWatchedToggle()
        }

        Task { @MainActor in
            season.tvShowDetails?.recalculateCachedProperties(triggerSync: true)
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
            }

            // Detach recalculation but ensure onToggle happens AFTER sync
            Task { @MainActor in
                episode.season?.tvShowDetails?.recalculateCachedProperties(triggerSync: true)
                withAnimation(.spring(duration: 0.2)) {
                    onToggle()
                }
            }
        } label: {
            let accent = themeColor.readableAccent(colorScheme: colorScheme)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text("E\(episode.episodeNumber)")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            episode.isWatched
                                ? Color.semanticGreen(for: colorScheme) : accent.opacity(0.15)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(episode.isWatched ? .white : accent)

                    Spacer()

                    if episode.isWatched {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.semanticGreen(for: colorScheme))
                            .font(.system(size: 14))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.name.isEmpty ? "Episode \(episode.episodeNumber)" : episode.name)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(height: 18, alignment: .topLeading)
                        .foregroundStyle(.primary)

                    Spacer()

                    HStack {
                        if let date = episode.airDateAsDate {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let runtime = episode.runtime, runtime > 0 {
                            Text("\(runtime)m")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        episode.isWatched
                            ? Color.semanticGreen(for: colorScheme).opacity(0.3)
                            : Color.primary.opacity(0.06), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.03), radius: 5, x: 0, y: 3)
        }
        .buttonStyle(.interactive(feedback: nil))
        .drawingGroup() // Rasterize for silky scrolling
        .scrollTransition { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.7)
                .scaleEffect(phase.isIdentity ? 1 : 0.92)
                .blur(radius: phase.isIdentity ? 0 : 2)
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
