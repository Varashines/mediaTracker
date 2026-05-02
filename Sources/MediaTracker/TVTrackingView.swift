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
        .onChange(of: tvDetails.seasons.count) { _, _ in
            if selectedSeasonNumber == nil {
                selectInitialSeason()
            }
        }
        .onChange(of: tvDetails.item?.lastUpdated) { _, _ in
            // If we are currently showing "No episodes" or nothing is selected,
            // re-run the selection logic because background data might have arrived.
            let currentSeason = tvDetails.seasons.first(where: { $0.seasonNumber == selectedSeasonNumber })
            if selectedSeasonNumber == nil || (currentSeason?.episodes.isEmpty ?? true) {
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
    var onWatchedToggle: () -> Void
    @Environment(\.colorScheme) var colorScheme

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)
    ]

    private var isAllWatched: Bool {
        !season.episodes.isEmpty && season.episodes.allSatisfy { $0.isWatched }
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
                        Image(systemName: isAllWatched ? "arrow.counterclockwise" : "checkmark.seal.fill")
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
                .disabled(season.episodes.isEmpty)
            }
            .padding(.horizontal, 4)

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
                        .background(episode.isWatched ? Color.semanticGreen(for: colorScheme) : accent.opacity(0.15))
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
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(height: 34, alignment: .topLeading)
                        .foregroundStyle(.primary)

                    if let date = episode.airDateAsDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(episode.isWatched ? Color.semanticGreen(for: colorScheme).opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.03), radius: 5, x: 0, y: 3)
        }
        .buttonStyle(.interactive(feedback: nil))
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
