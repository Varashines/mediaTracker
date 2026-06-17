import SwiftData
import SwiftUI

private enum TVTrackingConstants {
    static let cornerRadius: CGFloat = AppTheme.Radius.small
    static let cardCornerRadius: CGFloat = AppTheme.Radius.medium
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
    var onSeasonCompleted: (() -> Void)? = nil

    @State private var selectedSeasonNumber: Int?
    @State private var previousSeasonComplete = false

    private var sortedSeasons: [TVSeason] {
        tvDetails.seasons
            .liveModels
            .sorted(by: { $0.seasonNumber < $1.seasonNumber })
    }

    private var selectedSeasonIsComplete: Bool {
        guard let selectedNumber = selectedSeasonNumber,
              let season = tvDetails.seasons.first(where: { $0.seasonNumber == selectedNumber }),
              season.totalEpisodesCount > 0 else { return false }
        return season.watchedEpisodesCount == season.totalEpisodesCount
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
                    LazyHStack(spacing: 12) {
                        ForEach(sortedSeasons, id: \.seasonNumber) { season in
                            SeasonTab(
                                season: season,
                                isSelected: selectedSeasonNumber == season.seasonNumber,
                                themeColor: themeColor
                            ) {
                                withAnimation(AppTheme.Animation.easeInOut) {
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
                        previousSeasonComplete = selectedSeasonIsComplete
                    }
                }
            }
        }
        .onAppear { refreshSeasonSelection() }
        .onChange(of: tvDetails.seasons.count) { _, _ in refreshSeasonSelection() }
        .onChange(of: tvDetails.item?.lastUpdated) { _, _ in refreshSeasonSelection() }
        .onChange(of: selectedSeasonIsComplete) { _, isNowComplete in
            if isNowComplete && !previousSeasonComplete {
                onSeasonCompleted?()
            }
            previousSeasonComplete = isNowComplete
        }
    }

    private func autoFetchIfNeeded(season: TVSeason) {
        if season.totalEpisodesCount == 0 && season.episodes.isEmpty && season.episodeCount > 0
            && !isRefreshing
        {
            onSeasonSelected?(season)
        }
    }

    private func refreshSeasonSelection() {
        let currentSeason = tvDetails.seasons.first(where: {
            $0.seasonNumber == selectedSeasonNumber
        })
        if selectedSeasonNumber == nil || (currentSeason?.totalEpisodesCount == 0) {
            selectInitialSeason()
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
            let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
            HStack(spacing: 8) {
                Text(season.name.isEmpty ? "Season \(season.seasonNumber)" : season.name)

                if isFullyWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppTheme.Font.caption2)
                        .foregroundStyle(Color.semanticGreen(for: colorScheme))
                } else if progress > 0 {
                    Circle()
                        .trim(from: 0.0, to: CGFloat(progress))
                        .stroke(accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(width: 8, height: 8)
                        .rotationEffect(.degrees(-90))
                } else {
                    Circle()
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1.5)
                        .frame(width: 8, height: 8)
                }
            }
            .font(isSelected ? AppTheme.Font.bodyBold : AppTheme.Font.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(isSelected ? Color.primary.opacity(0.15) : Color.primary.opacity(0.03))
            }
            .overlay {
                Capsule()
                    .stroke(
                        isSelected ? accent.opacity(0.5) : Color.clear,
                        lineWidth: isSelected ? 1.5 : 1)
            }
            .foregroundStyle(isSelected ? Color.primary : .secondary)
            .accessibilityLabel("\(season.name.isEmpty ? "Season \(season.seasonNumber)" : season.name), \(Int(progress * 100))% watched")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .buttonStyle(.plain)
    }
}

private struct SeasonSection: View {
    @Bindable var season: TVSeason
    var themeColor: Color
    var isRefreshing: Bool = false
    var onWatchedToggle: () -> Void
    var onSeasonSelected: ((TVSeason) -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedRangeStart: Int = 1

    private let episodesPerRange = 10
    private let rangeThreshold = 15

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16)
    ]

    private var isAllWatched: Bool {
        season.totalEpisodesCount > 0 && season.watchedEpisodesCount == season.totalEpisodesCount
    }

    private var sortedEpisodes: [TVEpisode] {
        season.episodes.liveModels.sorted(by: { $0.episodeNumber < $1.episodeNumber })
    }

    private var showRangePills: Bool {
        sortedEpisodes.count > rangeThreshold
    }

    private var episodeRanges: [ClosedRange<Int>] {
        let episodes = sortedEpisodes
        guard !episodes.isEmpty else { return [] }

        let firstEp = episodes.first!.episodeNumber
        let lastEp = episodes.last!.episodeNumber
        var ranges: [ClosedRange<Int>] = []
        var start = firstEp
        while start <= lastEp {
            let end = min(start + episodesPerRange - 1, lastEp)
            ranges.append(start...end)
            start = end + 1
        }

        // Merge last range into previous if ≤ 1 episode
        if ranges.count >= 2 {
            let last = ranges[ranges.count - 1]
            let prev = ranges[ranges.count - 2]
            if last.count <= 1 {
                ranges[ranges.count - 2] = prev.lowerBound...last.upperBound
                ranges.removeLast()
            }
        }

        return ranges
    }

    private var filteredEpisodes: [TVEpisode] {
        if !showRangePills {
            return sortedEpisodes
        }
        guard let range = episodeRanges.first(where: { $0.lowerBound == selectedRangeStart }) else {
            return sortedEpisodes
        }
        return sortedEpisodes.filter { range.contains($0.episodeNumber) }
    }

    private func defaultRangeStart() -> Int {
        // Find the range containing the first unwatched episode
        if let firstUnwatched = sortedEpisodes.first(where: { !$0.isWatched }) {
            let epNum = firstUnwatched.episodeNumber
            for range in episodeRanges {
                if range.contains(epNum) {
                    return range.lowerBound
                }
            }
        }
        return 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Compact single-line header
            HStack(alignment: .center, spacing: 8) {
                Text(season.name.isEmpty ? "Season \(season.seasonNumber)" : season.name)
                    .font(AppTheme.Font.title3)

                if let date = season.airDate, let parsed = DateUtils.parseDate(date) {
                    Text(parsed.formatted(.dateTime.year()))
                        .font(AppTheme.Font.subtitle)
                        .foregroundStyle(.tertiary)
                }

                if season.episodeCount > 0 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(season.episodeCount) EPISODES")
                        .font(AppTheme.Font.caption2)
                        .foregroundStyle(.secondary)
                        .kerning(1.2)
                }

                if showRangePills {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    ForEach(episodeRanges.indices, id: \.self) { index in
                        let range = episodeRanges[index]
                        let rangeStart = range.lowerBound
                        let rangeEnd = range.upperBound
                        let isSelected = selectedRangeStart == rangeStart

                        Button {
                            withAnimation(AppTheme.Animation.springSnappy) {
                                selectedRangeStart = rangeStart
                            }
                        } label: {
                            Text("\(rangeStart)-\(rangeEnd)")
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .foregroundStyle(isSelected ? themeColor : .secondary)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? themeColor.opacity(0.12) : Color.primary.opacity(0.04))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? themeColor.opacity(0.25) : .clear, lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                Button {
                    toggleSeasonWatchedStatus()
                } label: {
                    HStack(spacing: 6) {
                        Image(
                            systemName: isAllWatched
                                ? "arrow.counterclockwise" : "checkmark.seal.fill")
                        Text(isAllWatched ? "Reset" : "Mark All")
                    }
                    .font(AppTheme.Font.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        isAllWatched
                            ? themeColor.opacity(colorScheme == .dark ? 0.1 : 0.05)
                            : themeColor.opacity(colorScheme == .dark ? 0.15 : 0.12)
                    )
                    .foregroundStyle(isAllWatched ? .secondary : themeColor)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(season.totalEpisodesCount == 0)
            }
            .padding(.horizontal, 4)

            if season.totalEpisodesCount == 0 {
                VStack(spacing: 16) {
                    Image(systemName: "sparkles.tv")
                        .font(AppTheme.Font.title2)
                        .foregroundStyle(.tertiary)

                    VStack(spacing: 2) {
                        Text("No episodes loaded")
                            .font(AppTheme.Font.bodyBold)
                            .foregroundStyle(.secondary)

                        if season.episodeCount > 0 {
                            Text("\(season.episodeCount) episodes available")
                                .font(AppTheme.Font.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if season.episodeCount > 0 {
                        Button {
                            onSeasonSelected?(season)
                        } label: {
                            if isRefreshing {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Fetch Episodes", systemImage: "arrow.down.circle.fill")
                                    .font(AppTheme.Font.bodyBold)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(isRefreshing)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(
                        filteredEpisodes,
                        id: \.persistentModelID
                    ) { ep in
                        EpisodeCube(episode: ep, themeColor: themeColor) {
                            onWatchedToggle()
                        }
                    }
                }
            }
        }
        .onAppear {
            if showRangePills && selectedRangeStart == 1 {
                selectedRangeStart = defaultRangeStart()
            }
        }
    }

    private func toggleSeasonWatchedStatus() {
        let targetStatus = !isAllWatched
        // Defensive: skip deleted/detached episodes during concurrent merges
        let liveEpisodes = season.episodes.liveModels
        withAnimation(AppTheme.Animation.springSnappy) {
            for episode in liveEpisodes {
                episode.markWatched(targetStatus)
            }
            onWatchedToggle()
        }

        Task { @MainActor in
            season.tvShowDetails?.recalculateCachedProperties(triggerSync: true)
            if let context = season.modelContext {
                SaveCoordinator.shared.requestSave(context)
            }
            let itemID = season.tvShowDetails?.item?.persistentModelID
            MediaStateService.shared.postMediaStateChanged(itemID: itemID)
        }
    }
}

// MARK: - Episode Cube

private struct EpisodeCube: View {
    @Bindable var episode: TVEpisode
    var themeColor: Color
    var onToggle: () -> Void
    @Environment(\.colorScheme) var colorScheme

    @State private var showingOverview = false
    @State private var isHovering = false

    var body: some View {
        let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
        let green = Color.semanticGreen(for: colorScheme)
        ZStack(alignment: .bottomTrailing) {
            Button {
                episode.markWatched(!episode.isWatched)
                FeedbackManager.shared.trigger(episode.isWatched ? .markWatched : .unmarkWatched)

                Task { @MainActor in
                    onToggle()
                    episode.season?.tvShowDetails?.recalculateCachedProperties(triggerSync: true)
                    if let context = episode.modelContext {
                        SaveCoordinator.shared.requestSave(context)
                    }
                    let itemID = episode.season?.tvShowDetails?.item?.persistentModelID
                    MediaStateService.shared.postMediaStateChanged(itemID: itemID)
                }
            } label: {
                HStack(spacing: 0) {
                    // Left accent bar
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(episode.isWatched ? green : Color.blue)
                        .frame(width: 3.5)
                        .padding(.vertical, 20)

                    VStack(alignment: .leading, spacing: 0) {
                        // Episode number
                        Text(String(format: "%02d", episode.episodeNumber))
                            .font(AppTheme.Font.bodyBold)
                            .foregroundStyle(episode.isWatched ? .secondary : .primary)

                        Spacer(minLength: 4)

                        // Title
                        Text(
                            episode.name.isEmpty ? "Episode \(episode.episodeNumber)" : episode.name
                        )
                        .font(AppTheme.Font.caption)
                        .lineLimit(2)
                        .foregroundStyle(episode.isWatched ? .secondary : .primary)

                        Spacer(minLength: 6)

                        // Metadata + Info button
                        HStack(spacing: 5) {
                            if let date = episode.airDateAsDate {
                                Text(date.formatted(.dateTime.month(.abbreviated).day()))
                                    .foregroundStyle(.secondary.opacity(0.6))
                            }
                            if episode.airDateAsDate != nil, let runtime = episode.runtime,
                                runtime > 0
                            {
                                Text("\u{00B7}")
                                    .foregroundStyle(.secondary.opacity(0.25))
                            }
                            if let runtime = episode.runtime, runtime > 0 {
                                Text("\(runtime)m")
                                    .foregroundStyle(.secondary.opacity(0.4))
                            }

                            Spacer()

                            if !episode.overview.isEmpty {
                                Button {
                                    showingOverview.toggle()
                                } label: {
                                    Image(systemName: "info.circle.fill")
                                        .font(AppTheme.Font.caption2)
                                        .foregroundStyle(
                                            accent.opacity(showingOverview ? 1.0 : 0.3)
                                        )
                                        .padding(.trailing, 4)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .highPriorityGesture(
                                    TapGesture().onEnded { showingOverview.toggle() }
                                )
                                .popover(isPresented: $showingOverview) {
                                    popoverContent
                                }
                            }
                        }
                        .font(AppTheme.Font.caption2)
                        .padding(.top, 5)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
                }
                .frame(maxWidth: .infinity, minHeight: 110)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.Colors.surfaceGhost(for: colorScheme))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(episode.isWatched ? green.opacity(0.12) : Color.blue.opacity(0.05))
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            episode.isWatched
                                ? green.opacity(0.3)
                                : (isHovering
                                    ? accent.opacity(0.25)
                                    : AppTheme.Colors.strokeDefault(for: colorScheme)),
                            lineWidth: 0.6
                        )
                }
                .shadow(
                    color: isHovering ? AppTheme.Shadow.elevated.color : AppTheme.Shadow.card.color,
                    radius: isHovering
                        ? AppTheme.Shadow.elevated.radius : AppTheme.Shadow.card.radius,
                    x: isHovering ? AppTheme.Shadow.elevated.x : AppTheme.Shadow.card.x,
                    y: isHovering ? AppTheme.Shadow.elevated.y : AppTheme.Shadow.card.y
                )
            }
            .buttonStyle(.interactive(feedback: nil))
            .accessibilityLabel("Episode \(episode.episodeNumber), \(episode.name.isEmpty ? "Episode \(episode.episodeNumber)" : episode.name), \(episode.isWatched ? "watched" : "not watched")")
            .accessibilityHint("Double tap to toggle watched")
            .onHover { hovering in
                withAnimation(AppTheme.Animation.easeInOut) { isHovering = hovering }
            }
        }
        .animation(AppTheme.Animation.springSnappy, value: episode.isWatched)
        .animation(AppTheme.Animation.springSnappy, value: isHovering)
    }

    // MARK: - Popover

    @ViewBuilder
    private var popoverContent: some View {
        let green = Color.semanticGreen(for: colorScheme)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("EPISODE \(episode.episodeNumber)")
                        .font(AppTheme.Font.small)
                        .foregroundStyle(.secondary)
                        .kerning(0.8)

                    Text(episode.name.isEmpty ? "Episode \(episode.episodeNumber)" : episode.name)
                        .font(AppTheme.Font.bodyBold)
                        .foregroundStyle(.primary)
                }

                Spacer()

                if episode.isWatched {
                    Text("WATCHED")
                        .font(AppTheme.Font.tiny)
                        .foregroundStyle(.secondary)
                        .kerning(0.6)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                        .background(green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }

            let dateString: String? = episode.airDateAsDate?.formatted(
                date: .abbreviated, time: .omitted)
            let runtimeString: String? = (episode.runtime ?? 0) > 0 ? "\(episode.runtime!)m" : nil

            if dateString != nil || runtimeString != nil {
                HStack(spacing: 0) {
                    if let dateStr = dateString { Text(dateStr) }
                    if dateString != nil && runtimeString != nil {
                        Text(" \u{00B7} ").foregroundStyle(.secondary.opacity(0.5))
                    }
                    if let runStr = runtimeString { Text(runStr) }
                }
                .font(AppTheme.Font.label)
                .foregroundStyle(.secondary)
            }

            if !episode.overview.isEmpty {
                ScrollView(showsIndicators: false) {
                    Text(episode.overview)
                        .font(AppTheme.Font.label)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(width: 270)
        .fixedSize(horizontal: false, vertical: true)
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

        return TVTrackingView(tvDetails: details, themeColor: AppTheme.Colors.accent) {}
            .padding()
    }
#endif
