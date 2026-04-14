import SwiftUI
import SwiftData

struct TVTrackingView: View {
    var tvDetails: TVShowDetails
    var onWatchedToggle: () -> Void
    
    @State private var selectedSeasonNumber: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            
            if tvDetails.seasons.isEmpty {
                Text("No season data available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Horizontal Season Selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(tvDetails.seasons.sorted(by: { $0.seasonNumber < $1.seasonNumber }), id: \.seasonNumber) { season in
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
                    .padding(.vertical, 4)
                }
                
                // Focused Episode Grid
                if let selectedNumber = selectedSeasonNumber,
                   let selectedSeason = tvDetails.seasons.first(where: { $0.seasonNumber == selectedNumber }) {
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

    private var header: some View {
        HStack(spacing: 12) {
            if let status = tvDetails.status, !status.isEmpty {
                Label(status, systemImage: "tv")
            }
            if let eps = tvDetails.numberOfEpisodes {
                Label("\(eps) eps", systemImage: "number")
            }
            if let seasons = tvDetails.numberOfSeasons {
                Label("\(seasons) seasons", systemImage: "square.grid.2x2")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    
    private func selectInitialSeason() {
        let sortedSeasons = tvDetails.seasons.sorted(by: { $0.seasonNumber < $1.seasonNumber })
        
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
    
    var isFullyWatched: Bool {
        !season.episodes.isEmpty && season.episodes.allSatisfy { $0.isWatched }
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("Season \(season.seasonNumber)")
                    .font(.system(.subheadline, weight: isSelected ? .bold : .medium))
                
                if isFullyWatched {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.green)
                } else if season.episodes.contains(where: { $0.isWatched }) {
                    // Partially watched indicator
                    Capsule()
                        .fill(Color.green.opacity(0.5))
                        .frame(width: 20, height: 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 1)
            )
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

private struct SeasonSection: View {
    @Bindable var season: TVSeason
    var onWatchedToggle: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Season \(season.seasonNumber)")
                    .font(.headline)
                if let date = season.airDate, let parsed = DateUtils.parseDate(date) {
                    Text("(\(parsed.formatted(.dateTime.year())))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if season.episodeCount > 0 {
                    Text("\(season.episodeCount) eps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if season.episodes.isEmpty {
                Text("No episodes loaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(season.episodes.sorted(by: { $0.episodeNumber < $1.episodeNumber }), id: \.episodeNumber) { ep in
                        EpisodeCube(episode: ep) {
                            onWatchedToggle()
                        }
                    }
                }
            }
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
                        .background(episode.isWatched ? Color.green.opacity(0.2) : Color.accentColor.opacity(0.1))
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
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(episode.isWatched ? Color.green.opacity(0.3) : Color.primary.opacity(0.05), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview {
    // Minimal placeholder data for preview; adjust to your models if needed
    let details = TVShowDetails(tmdbID: 0)
    let season1 = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 2, airDate: nil)
    let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Pilot", overview: "", airDate: nil, runtime: 42)
    let ep2 = TVEpisode(episodeNumber: 2, seasonNumber: 1, name: "Second", overview: "", airDate: nil, runtime: 44)
    ep1.season = season1
    ep2.season = season1
    season1.episodes = [ep1, ep2]
    details.seasons = [season1]
    return TVTrackingView(tvDetails: details) {}
        .padding()
}
#endif
