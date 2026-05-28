import SwiftData
import SwiftUI

@MainActor
struct MediaThumbnailView: View {
    enum DisplayMode {
        case grid
        case hero
        case search
    }

    var item: MediaItem?
    let metadata: MediaThumbnailMetadata?
    let result: MediaSearchResult?
    let mode: DisplayMode
    var showTypeBadge: Bool = true
    var isUpcomingSection: Bool = false
    var isLocalInSearch: Bool = false
    var namespace: Namespace.ID? = nil
    var staggerIndex: Int? = nil
    var isFastScrolling: Bool = false
    var disableHover: Bool = false
    var action: (() -> Void)? = nil

    // Captured values for stability during background updates or deletion
    private let capturedID: PersistentIdentifier?
    private let capturedItemID: String
    private let capturedTitle: String
    private let capturedPosterURL: String?
    private let capturedType: MediaType
    private let capturedState: MediaState
    private let capturedProgress: Double?
    private let capturedReleaseDate: Date?
    private let capturedThemeColorHex: String?
    private let capturedNextEpisodeLabel: String?
    private let capturedWatchProgress: String?
    private let capturedIsUpcoming: Bool
    private let capturedGridBadgeText: String?
    private let capturedNextAiringDate: Date?
    private let capturedDisplayYear: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme

    @State private var isHovered = false
    @State private var isButtonHovered = false
    @State private var isAppeared = false
    @State private var isRemoved = false

    // Performance optimization: Status passed from parent to avoid @Query in every thumbnail
    var isCompletedInCollection: Bool = false
    var selectedCollectionID: UUID? = nil

    init(
        item: MediaItem, mode: DisplayMode = .grid, showTypeBadge: Bool = true,
        isUpcomingSection: Bool = false,
        namespace: Namespace.ID? = nil, staggerIndex: Int? = nil, isFastScrolling: Bool = false,
        disableHover: Bool = false,
        isCompletedInCollection: Bool = false, selectedCollectionID: UUID? = nil,
        action: (() -> Void)? = nil
    ) {
        self.item = item
        self.metadata = nil
        self.result = nil
        self.mode = mode
        self.showTypeBadge = showTypeBadge
        self.isUpcomingSection = isUpcomingSection
        self.namespace = namespace
        self.staggerIndex = staggerIndex
        self.isFastScrolling = isFastScrolling
        self.disableHover = disableHover
        self.isCompletedInCollection = isCompletedInCollection
        self.selectedCollectionID = selectedCollectionID
        self.action = action

        // IMMEDIATE CAPTURE - This prevents crashes if item is deleted later
        self.capturedID = item.persistentModelID
        self.capturedItemID = item.id
        self.capturedTitle = item.title
        self.capturedPosterURL = item.posterURL
        self.capturedType = item.type ?? .movie
        self.capturedState = item.state ?? .wishlist
        self.capturedProgress = item.storedProgress
        self.capturedReleaseDate = item.releaseDate
        self.capturedThemeColorHex = item.themeColorHex
        self.capturedNextEpisodeLabel = item.storedNextEpisodeLabel
        self.capturedWatchProgress = item.storedWatchProgressLabel
        self.capturedIsUpcoming = item.isUpcoming
        self.capturedGridBadgeText = item.badgeText
        self.capturedNextAiringDate = item.cachedNextAiringDate
        self.capturedDisplayYear = item.releaseDate.flatMap { Calendar.current.dateComponents([.year], from: $0).year.map { String($0) } }
    }

    init(
        metadata: MediaThumbnailMetadata, mode: DisplayMode = .grid, showTypeBadge: Bool = true,
        isUpcomingSection: Bool = false,
        namespace: Namespace.ID? = nil, staggerIndex: Int? = nil, isFastScrolling: Bool = false,
        disableHover: Bool = false,
        isCompletedInCollection: Bool = false, selectedCollectionID: UUID? = nil,
        action: (() -> Void)? = nil
    ) {
        self.item = nil
        self.metadata = metadata
        self.result = nil
        self.mode = mode
        self.showTypeBadge = showTypeBadge
        self.isUpcomingSection = isUpcomingSection
        self.namespace = namespace
        self.staggerIndex = staggerIndex
        self.isFastScrolling = isFastScrolling
        self.disableHover = disableHover
        self.isCompletedInCollection = isCompletedInCollection
        self.selectedCollectionID = selectedCollectionID
        self.action = action

        self.capturedID = metadata.id
        self.capturedItemID = metadata.itemID
        self.capturedTitle = metadata.title
        self.capturedPosterURL = metadata.posterURL
        self.capturedType = metadata.type ?? .movie
        self.capturedState = metadata.state ?? .wishlist
        self.capturedProgress = metadata.progress
        self.capturedReleaseDate = metadata.releaseDate
        self.capturedThemeColorHex = metadata.themeColorHex
        self.capturedNextEpisodeLabel = metadata.nextEpisodeToWatchLabel
        self.capturedWatchProgress = metadata.watchProgress
        self.capturedIsUpcoming = metadata.isUpcoming
        self.capturedGridBadgeText = metadata.badgeText
        self.capturedNextAiringDate = metadata.nextAiringDate
        self.capturedDisplayYear = metadata.releaseDate.flatMap { Calendar.current.dateComponents([.year], from: $0).year.map { String($0) } }
    }

    init(result: MediaSearchResult, isLocal: Bool = false, action: @escaping () -> Void) {
        self.item = nil
        self.metadata = nil
        self.result = result
        self.mode = .search
        self.isLocalInSearch = isLocal
        self.action = action
        self.namespace = nil
        self.staggerIndex = nil

        self.capturedID = nil
        self.capturedItemID = ""
        self.capturedTitle = result.title
        self.capturedPosterURL = result.posterURL
        self.capturedType = result.type
        self.capturedState = .wishlist
        self.capturedProgress = 0
        self.capturedReleaseDate = result.releaseDate.flatMap { DateUtils.parseDate($0) }
        self.capturedThemeColorHex = nil
        self.capturedNextEpisodeLabel = nil
        self.capturedWatchProgress = nil
        self.capturedIsUpcoming = false
        self.capturedGridBadgeText = nil
        self.capturedNextAiringDate = result.releaseDate.flatMap { DateUtils.parseDate($0) }
        self.capturedDisplayYear = capturedReleaseDate.flatMap { Calendar.current.dateComponents([.year], from: $0).year.map { String($0) } }
    }

    private var width: CGFloat {
        switch mode {
        case .hero: return 200
        default: return 160
        }
    }

    private var height: CGFloat {
        switch mode {
        case .hero: return 300
        default: return 240
        }
    }

    private var title: String { capturedTitle }
    private var posterURL: String? { capturedPosterURL }
    private var type: MediaType { capturedType }
    private var safeState: MediaState { capturedState }
    private var safeProgress: Double? { capturedProgress }

    private var yearLabel: String? { capturedDisplayYear }

    private var isAdded: Bool {
        return (item != nil || capturedID != nil) || isLocalInSearch
    }

    private var nextEpisodeLabel: String? { capturedNextEpisodeLabel }
    private var watchProgress: String? { capturedWatchProgress }
    private var isUpcoming: Bool { capturedIsUpcoming }
    private var gridBadgeText: String? { capturedGridBadgeText }
    private var nextAiringDate: Date? { capturedNextAiringDate }

    var body: some View {
        Group {
            if !isRemoved {
                if let action = action {
                    Button(action: action) {
                        mainContent
                    }
                    .buttonStyle(.interactive)
                } else {
                    mainContent
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .contextMenu {
            if !isRemoved, let id = capturedID {
                libraryContextMenu(
                    for: id, type: capturedType, state: capturedState, progress: capturedProgress)
            }
        }
    }

    private var accessibilityLabel: String {
        var parts = [title]
        parts.append(type.rawValue)

        if isUpcoming, let badge = gridBadgeText {
            parts.append("Releases on \(badge)")
        } else {
            parts.append(safeState.displayName)
            if let progress = watchProgress {
                parts.append(progress)
            }
        }

        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var mainContent: some View {
        let hasNoPoster = (posterURL == nil || posterURL?.isEmpty == true)
        let effectiveHover = isHovered || hasNoPoster

        let posterContent = ZStack(alignment: .center) {
            // 1. Poster Layer
            ThumbnailPosterLayer(
                posterURL: posterURL,
                themeColorHex: item?.themeColorHex ?? capturedThemeColorHex,
                mode: mode,
                type: type,
                isFastScrolling: isFastScrolling,
                width: width,
                height: height
            )

            // 2. Hover Metadata Pills (Floating capsules)
            HoverMetadataPills(
                title: title,
                year: yearLabel,
                nextEpisodeLabel: nextEpisodeLabel,
                nextAiringDate: nextAiringDate,
                isUpcoming: isUpcoming,
                isHovered: effectiveHover
            )

            // Smart Badge (Top Leading)
            VStack {
                HStack {
                    if !isRemoved {
                        if let item = item, item.modelContext != nil, !item.isDeleted {
                            SmartBadgeView(item: item)
                        } else if let metadata = metadata {
                            SmartBadgeView(metadata: metadata)
                        }
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(8)
            .opacity(isHovered ? 0 : 1)
            .offset(x: isHovered ? -4 : 0, y: isHovered ? -4 : 0)

            // Top Trailing Badges
            if isCompletedInCollection || showTypeBadge {
                VStack {
                    HStack {
                        Spacer()
                        if showTypeBadge {
                            typeBadge
                        }
                        if isCompletedInCollection {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }
                    }
                    Spacer()
                }
                .padding(8)
                .opacity(isHovered ? 0 : 1)
                .offset(x: isHovered ? 4 : 0, y: isHovered ? -4 : 0)
            }
        }

        let itemIDString: String = {
            if let id = capturedID { return "\(id)" }
            return result?.id ?? ""
        }()

        ZStack {
            if let ns = namespace, mode == .hero, !isFastScrolling && !itemIDString.isEmpty {
                posterContent
                    .matchedGeometryEffect(id: "poster_\(itemIDString)", in: ns)
                    .background {
                        Color.clear.matchedGeometryEffect(id: "poster_bg_\(itemIDString)", in: ns)
                    }
            } else {
                posterContent
            }

            // 3. Search Mode (Modal status remains visible)
            if mode == .search {
                ThumbnailSearchOverlay(
                    isAdded: isAdded,
                    isLocalInSearch: isLocalInSearch,
                    isHovered: isHovered
                )
            }
        }
        .frame(width: width, height: height)
        .cornerRadius(AppTheme.Radius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                .stroke(disableHover && isHovered ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 2)
                .animation(.easeOut(duration: 0.15), value: isHovered)
        )
        .drawingGroup(opaque: false)
        .opacity(isAppeared ? 1 : (isFastScrolling ? 1 : 0))
        .scaleEffect(!disableHover && isHovered ? 1.03 : (isAppeared ? 1 : (isFastScrolling ? 1 : 0.9)))
        .offset(y: (isAppeared || isFastScrolling) ? 0 : 20)
        .onAppear {
            if isFastScrolling {
                isAppeared = true
                return
            }
            let delay = Double(staggerIndex ?? 0 % 15) * 0.05
            withAnimation(AppTheme.Animation.springGentle.delay(delay)) {
                isAppeared = true
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            guard !disableHover else { return }
            isHovered = hovering
        }
        .animation(!disableHover ? AppTheme.Animation.springSnappy : nil, value: isHovered)
    }

    private func markNextEpisodeAsWatched(for item: MediaItem) {
        guard item.modelContext != nil, let tv = item.tvShowDetails else { return }

        // Optimize: Find first unwatched season first
        let sortedSeasons = tv.seasons.sorted { $0.seasonNumber < $1.seasonNumber }
        guard
            let currentSeason = sortedSeasons.first(where: {
                $0.watchedEpisodesCount < $0.totalEpisodesCount
            })
        else { return }

        let sortedEpisodes = currentSeason.episodes.sorted { $0.episodeNumber < $1.episodeNumber }

        if let next = sortedEpisodes.first(where: { !$0.isWatched }) {
            next.markWatched(true)
            item.lastInteractionDate = Date()
            Task { @MainActor in
                item.checkOverallCompletion()
                item.syncCachedProperties()
                if let context = item.modelContext {
                    SaveCoordinator.shared.requestSave(context)
                }
                MediaStateService.shared.postMediaStateChanged(itemID: item.persistentModelID)
            }
        }
    }

    private var typeBadge: some View {
        let themeColor = item?.themeColorHex.flatMap { Color(hex: $0) } ?? capturedThemeColorHex.flatMap { Color(hex: $0) } ?? Color.accentColor
        let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
        let bgAccent = themeColor.luminousAccent(colorScheme: colorScheme)
        
        return Group {
            switch type {
            case .movie:
                Image(systemName: "film")
            case .tvShow:
                Image(systemName: "tv")
            }
        }
        .font(.system(size: 9, weight: .bold))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .foregroundStyle(accent)
        .background {
            Capsule()
                .fill(bgAccent.opacity(colorScheme == .dark ? 0.25 : 0.35))
        }
        .overlay {
            Capsule().stroke(accent.opacity(0.15), lineWidth: 0.5)
        }
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func libraryContextMenu(
        for itemID: PersistentIdentifier, type: MediaType, state: MediaState, progress: Double?
    ) -> some View {
        if let collectionID = selectedCollectionID {
            let itemIDString = capturedItemID
            let isSeenInCollection = isCompletedInCollection

            Section("Collection Actions") {
                Button {
                    Task { @MainActor in
                        let descriptor = FetchDescriptor<MediaCollection>(
                            predicate: #Predicate { $0.id == collectionID })
                        if let collection = try? modelContext.fetch(descriptor).first {
                            if isSeenInCollection {
                                collection.completedItemIDs.removeAll { $0 == itemIDString }
                            } else {
                                collection.completedItemIDs.append(itemIDString)
                            }
                            SaveCoordinator.shared.requestSave(modelContext)
                        }
                        MediaStateService.shared.postMediaStateChanged(itemID: itemID)
                    }
                } label: {
                    Label(
                        isSeenInCollection
                            ? "Mark as Unseen in Collection" : "Mark as Seen in Collection",
                        systemImage: isSeenInCollection ? "circle" : "checkmark.circle.fill")
                }
            }
        }

        Section("Quick Tracking") {
            if type == .tvShow {
                Button {
                    if let item = modelContext.model(for: itemID) as? MediaItem, !item.isDeleted {
                        markNextEpisodeAsWatched(for: item)
                    }
                } label: {
                    Label("Mark Next Episode Watched", systemImage: "play.circle.fill")
                }
            }

            if state != .completed {
                Button {
                    if let item = modelContext.model(for: itemID) as? MediaItem {
                        withAnimation {
                            item.state = .completed
                            item.lastUpdated = Date()
                            SaveCoordinator.shared.requestSave(modelContext)
                        }
                    }
                } label: {
                    Label("Mark as Completed", systemImage: "checkmark.seal.fill")
                }
            }
        }

        Section("Set Status") {
            ForEach(MediaItem.availableStates(for: type, progress: progress), id: \.self) {
                targetState in
                Button(targetState.displayName) {
                    if let item = modelContext.model(for: itemID) as? MediaItem {
                        withAnimation {
                            item.state = targetState
                            item.lastUpdated = Date()
                            SaveCoordinator.shared.requestSave(modelContext)
                        }
                    }
                }
            }
        }

        Button(role: .destructive) {
            withAnimation {
                isRemoved = true
                FeedbackManager.shared.trigger(.removeFromLibrary)
            }

            if let item = modelContext.model(for: itemID) as? MediaItem, !item.isDeleted {
                let id = item.id
                NotificationManager.shared.cancelNotification(id: id, type: type)
                modelContext.delete(item)

            }
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }
}

#Preview("Media Thumbnail - Movie") {
    @Previewable var namespace = Namespace().wrappedValue
    
    let container = try! ModelContainer(
        for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, MediaCollection.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let item = MediaItem(id: "mt1", title: "The Matrix", overview: "A computer hacker learns about reality", type: .movie)
    item.state = .completed
    context.insert(item)
    
    return MediaThumbnailView(
        item: item,
        mode: .grid,
        showTypeBadge: true,
        isUpcomingSection: false,
        namespace: namespace,
        isFastScrolling: false,
        isCompletedInCollection: false,
        selectedCollectionID: nil
    )
    .frame(width: 160)
    .modelContainer(container)
}

struct ThumbnailPosterLayer: View {
    let posterURL: String?
    let themeColorHex: String?
    let mode: MediaThumbnailView.DisplayMode
    let type: MediaType
    let isFastScrolling: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            if let urlString = posterURL, let url = URL(string: urlString) {
                let baseColor = themeColorHex.flatMap { Color(hex: $0) }
                let targetSize: CGSize = mode == .hero ? .thumbMedium : .thumbSmall

                CachedImage(url: url, targetSize: targetSize, themeColor: baseColor, isFastScrolling: isFastScrolling) {
                    _ in
                } placeholder: {
                    Rectangle().fill(Color.secondary.opacity(0.1))
                        .overlay { ProgressView().controlSize(.small) }
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .overlay {
                        Image(systemName: type == .movie ? "film" : "tv")
                            .font(.system(size: mode == .hero ? 40 : 30))
                            .foregroundStyle(.secondary.opacity(0.2))
                    }
                    .frame(width: width, height: height)
            }
        }
    }
}

struct ThumbnailSearchOverlay: View {
    let isAdded: Bool
    let isLocalInSearch: Bool
    let isHovered: Bool

    var body: some View {
        if isAdded {
            ZStack {
                if !isLocalInSearch {
                    Rectangle()
                        .fill(.black.opacity(0.6))

                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.green)
                        Text("In Library")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                } else if isHovered {
                    Rectangle()
                        .fill(.black.opacity(0.2))
                }
            }
        } else if isHovered {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                        .padding(12)
                }
            }
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .top, endPoint: .bottom)
            )
        }
    }
}
