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
    var tvDetails: TVShowDetails
    var onWatchedToggle: () -> Void

    @State private var selectedSeasonNumber: Int?

    private var sortedSeasons: [TVSeason] {
        tvDetails.seasons.sorted(by: { $0.seasonNumber < $1.seasonNumber })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            if tvDetails.seasons.isEmpty {
                ContentUnavailableView("No season data", systemImage: "tv.slash", description: Text("Season information hasn't been loaded yet."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Horizontal Season Selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(sortedSeasons, id: \.seasonNumber) { season in
                            SeasonTab(
                                season: season,
                                isSelected: selectedSeasonNumber == season.seasonNumber
                            ) {
                                withAnimation(.spring(duration: 0.3)) {
                                    selectedSeasonNumber = season.seasonNumber
                                }
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
                    SeasonSection(season: selectedSeason, onWatchedToggle: onWatchedToggle)
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
        } else {
            // 2. Default to the last season if all are watched
            selectedSeasonNumber = sortedSeasons.last?.seasonNumber
        }
    }
}

private struct SeasonTab: View {
    let season: TVSeason
    let isSelected: Bool
    let action: () -> Void

    @State private var isAnimatingGlow = false

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
            Text("Season \(season.seasonNumber)")
                .font(.system(.subheadline, weight: isSelected ? .bold : .medium))
                .padding(.horizontal, 30)
                .padding(.vertical, 10)
                .foregroundStyle(
                    isSelected ? Color.accentColor : (isFullyWatched ? Color.green : .primary)
                )
                .background(
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: TVTrackingConstants.cornerRadius)
                                .fill(Color.accentColor.opacity(0.1))
                        }

                        if isFullyWatched {
                            RoundedRectangle(cornerRadius: TVTrackingConstants.cornerRadius)
                                .fill(Color.green.opacity(0.12))
                        } else if isOngoing {
                            RoundedRectangle(cornerRadius: TVTrackingConstants.cornerRadius)
                                .fill(Color.blueToGreen(progress: progress).opacity(0.1))
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: TVTrackingConstants.cornerRadius)
                        .stroke(borderColor, lineWidth: isFullyWatched || progress == 0 ? TVTrackingConstants.strokeWidth : TVTrackingConstants.secondaryStrokeWidth)
                        .overlay(
                            progressOverlay
                        )
                )
        }
        .buttonStyle(.plain)
        .onAppear { toggleAnimation() }
        .onChange(of: progress) { toggleAnimation() }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    private var borderColor: Color {
        if isFullyWatched { return Color.green.opacity(0.8) }
        if progress == 0 { return Color.blue.opacity(0.8) }
        return Color.primary.opacity(0.1)
    }

    @ViewBuilder
    private var progressOverlay: some View {
        if isOngoing {
            ZStack {
                RoundedRectangle(cornerRadius: TVTrackingConstants.cornerRadius)
                    .trim(from: 0, to: progress)
                    .stroke(Color.green, lineWidth: TVTrackingConstants.strokeWidth)
                
                RoundedRectangle(cornerRadius: TVTrackingConstants.cornerRadius)
                    .trim(from: progress, to: 1)
                    .stroke(Color.blue.opacity(0.9), lineWidth: TVTrackingConstants.strokeWidth)
            }
        }
    }

    private func toggleAnimation() {
        if isOngoing {
            withAnimation(.easeInOut(duration: TVTrackingConstants.animationDuration).repeatForever(autoreverses: true)) {
                isAnimatingGlow = true
            }
        } else {
            isAnimatingGlow = false
        }
    }
}

private struct SeasonSection: View {
    @Bindable var season: TVSeason
    var onWatchedToggle: () -> Void

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
                    Label(isAllWatched ? "Clear Season" : "Mark Season Watched", systemImage: isAllWatched ? "xmark.circle" : "checkmark.circle")
                        .font(.caption.bold())
                        .foregroundStyle(isAllWatched ? Color.secondary : Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isAllWatched ? Color.secondary.opacity(0.1) : Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(season.episodes.isEmpty)
            }

            if season.episodes.isEmpty {
                ContentUnavailableView("No episodes", systemImage: "sparkles.tv", description: Text("Episode data is not available for this season."))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(
                        season.episodes.sorted(by: { $0.episodeNumber < $1.episodeNumber }),
                        id: \.episodeNumber
                    ) { ep in
                        EpisodeCube(episode: ep) {
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
            onWatchedToggle()
        }
    }
}

private struct EpisodeCube: View {
    @Bindable var episode: TVEpisode
    var onToggle: () -> Void

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.2)) {
                episode.isWatched.toggle()
                onToggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text("E\(episode.episodeNumber)")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            episode.isWatched
                                ? Color.green.opacity(0.2) : Color.accentColor.opacity(0.1)
                        )
                        .foregroundStyle(episode.isWatched ? .green : .accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Spacer()

                    if episode.isWatched {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
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
        .buttonStyle(.plain)
    }
}

#if DEBUG
    #Preview {
        let details = TVShowDetails(tmdbID: 0)
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
        details.seasons = [season1]
        return TVTrackingView(tvDetails: details) {}
            .padding()
    }
#endif
