import SwiftData
import SwiftUI

private enum TVTrackingConstants {
    static let cornerRadius: CGFloat = 10
    static let cardCornerRadius: CGFloat = 12
    static let strokeWidth: CGFloat = 2.0
    static let secondaryStrokeWidth: CGFloat = 1.5
    static let animationDuration: Double = 1.2
}

struct TVTrackingView: View {
    @Bindable var tvDetails: TVShowDetails
    var themeColor: Color
    var isRefreshing: Bool = false
    var onWatchedToggle: () -> Void
    var onSeasonSelected: ((TVSeason) -> Void)? = nil
    
    @AppStorage("theme_style") private var themeStyle: ThemeStyle = .standard

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
                                withAnimation(.smooth) {
                                    selectedSeasonNumber = season.seasonNumber
                                }
                                onSeasonSelected?(season)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
                .scrollBounceBehavior(.basedOnSize)

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
    @AppStorage("theme_style") private var themeStyle: ThemeStyle = .standard

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
            let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
            let bgAccent = themeColor.luminousAccent(colorScheme: colorScheme)
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
                        .fill(bgAccent.opacity(colorScheme == .dark ? 0.3 : 0.4))
                } else {
                    Capsule()
                        .fill(themeColor.opacity(colorScheme == .dark ? 0.15 : 0.08))
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
                        .stroke(accent.opacity(0.3), lineWidth: 1)
                }
            }
            .foregroundStyle(isSelected ? accent : .secondary)
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
    @AppStorage("theme_style") private var themeStyle: ThemeStyle = .standard

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
                    let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
                    HStack(spacing: 6) {
                        Image(
                            systemName: isAllWatched
                                ? "arrow.counterclockwise" : "checkmark.seal.fill")
                        Text(isAllWatched ? "Reset" : "Mark All")
                    }
                    .font(.system(size: 11, weight: .black))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isAllWatched ? themeColor.opacity(colorScheme == .dark ? 0.1 : 0.05) : accent.opacity(colorScheme == .dark ? 0.15 : 0.12))
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
                        .tint(themeColor.highContrastAccent(colorScheme: colorScheme))
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
                episode.markWatched(targetStatus)
            }
            onWatchedToggle()
        }

        Task { @MainActor in
            season.tvShowDetails?.recalculateCachedProperties(triggerSync: true)
            if let context = season.modelContext {
                SaveCoordinator.shared.requestSave(context)
            }
            NotificationCenter.default.post(name: .mediaStateChanged, object: nil)
        }
    }
}

private struct EpisodeCube: View {
    @Bindable var episode: TVEpisode
    var themeColor: Color
    var onToggle: () -> Void
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("theme_style") private var themeStyle: ThemeStyle = .standard
    @State private var showingOverview = false

    var body: some View {
        let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
        
        ZStack(alignment: .bottomTrailing) {
            Button {
                withAnimation(.smooth) {
                    episode.markWatched(!episode.isWatched)
                    FeedbackManager.shared.trigger(episode.isWatched ? .markWatched : .unmarkWatched)
                }

                Task { @MainActor in
                    episode.season?.tvShowDetails?.recalculateCachedProperties(triggerSync: true)
                    withAnimation(.smooth) {
                        onToggle()
                    }
                    if let context = episode.modelContext {
                        SaveCoordinator.shared.requestSave(context)
                    }
                    NotificationCenter.default.post(name: .mediaStateChanged, object: nil)
                }
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    // Header: Episode Label & Watched Status
                    HStack(alignment: .center) {
                        Text("E\(episode.episodeNumber)")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                episode.isWatched
                                    ? Color.semanticGreen(for: colorScheme) 
                                    : accent.opacity(colorScheme == .dark ? 0.2 : 0.15)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(episode.isWatched ? .white : accent)

                        Spacer()

                        if episode.isWatched {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.semanticGreen(for: colorScheme))
                                .font(.system(size: 15, weight: .bold))
                        }
                    }

                    // Content: Title
                    Text(episode.name.isEmpty ? "Episode \(episode.episodeNumber)" : episode.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    // Footer: Date & Runtime
                    HStack(spacing: 8) {
                        if let date = episode.airDateAsDate {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let runtime = episode.runtime, runtime > 0 {
                            Text("\(runtime)m")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary.opacity(0.8))
                        }
                        
                        // Empty space to prevent overlap with info button
                        if !episode.overview.isEmpty {
                            Color.clear.frame(width: 14)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(themeColor.opacity(colorScheme == .dark ? 0.12 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            episode.isWatched
                                ? Color.semanticGreen(for: colorScheme).opacity(0.2)
                                : themeColor.opacity(0.2), lineWidth: 1.5)
                }
            }
            .buttonStyle(.interactive(feedback: nil))

            // Info Button (Integrated into bottom right)
            if !episode.overview.isEmpty {
                Button {
                    showingOverview.toggle()
                } label: {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(accent.opacity(showingOverview ? 1.0 : 0.4))
                        .padding(12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingOverview) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("EPISODE \(episode.episodeNumber)")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(accent.opacity(0.8))
                                .kerning(1)
                            
                            Text(episode.name)
                                .font(.system(size: 18, weight: .black, design: .rounded))
                        }
                        
                        Divider()
                        
                        ScrollView {
                            Text(episode.overview)
                                .font(.system(size: 13, weight: .medium))
                                .lineSpacing(4)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(20)
                    .frame(width: 320, height: 220)
                }
            }
        }
        .animation(.spring(response: 0.3), value: episode.isWatched)
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
