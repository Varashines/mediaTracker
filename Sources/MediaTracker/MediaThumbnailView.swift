import SwiftData
import SwiftUI

@MainActor
struct MediaThumbnailView: View, Equatable {
    nonisolated static func == (lhs: MediaThumbnailView, rhs: MediaThumbnailView) -> Bool {
        return lhs.capturedID == rhs.capturedID && lhs.capturedItemID == rhs.capturedItemID
            && lhs.capturedTitle == rhs.capturedTitle
            && lhs.capturedPosterURL == rhs.capturedPosterURL
            && lhs.capturedType == rhs.capturedType && lhs.capturedState == rhs.capturedState
            && lhs.capturedProgress == rhs.capturedProgress
            && lhs.isCompletedInCollection == rhs.isCompletedInCollection
            && lhs.selectedCollectionID == rhs.selectedCollectionID
            && lhs.capturedIsUpcoming == rhs.capturedIsUpcoming
            && lhs.capturedGridBadgeText == rhs.capturedGridBadgeText
    }

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
    }

    init(
        metadata: MediaThumbnailMetadata, mode: DisplayMode = .grid, showTypeBadge: Bool = true,
        isUpcomingSection: Bool = false,
        namespace: Namespace.ID? = nil, staggerIndex: Int? = nil, isFastScrolling: Bool = false,
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

    private var title: String { item?.title ?? capturedTitle }
    private var posterURL: String? { item?.posterURL ?? capturedPosterURL }
    private var type: MediaType { item?.type ?? capturedType }
    private var safeState: MediaState { item?.state ?? capturedState }
    private var safeProgress: Double? { item?.storedProgress ?? capturedProgress }

    private var yearLabel: String? {
        if let date = item?.releaseDate ?? capturedReleaseDate {
            return Calendar.current.dateComponents([.year], from: date).year.map { String($0) }
        }
        return nil
    }

    private var isAdded: Bool {
        return (item != nil || capturedID != nil) || isLocalInSearch
    }

    private var nextEpisodeLabel: String? {
        item?.storedNextEpisodeLabel ?? capturedNextEpisodeLabel
    }
    private var watchProgress: String? { item?.storedWatchProgressLabel ?? capturedWatchProgress }
    private var isUpcoming: Bool { item?.isUpcoming ?? capturedIsUpcoming }
    private var gridBadgeText: String? { item?.badgeText ?? capturedGridBadgeText }
    private var nextAiringDate: Date? { item?.cachedNextAiringDate ?? capturedNextAiringDate }

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
                height: height,
                namespace: nil,  // Moved to root
                capturedID: nil,
                resultID: nil
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
        .cornerRadius(16)
        .opacity(isAppeared ? 1 : (isFastScrolling ? 1 : 0))
        .scaleEffect(isHovered ? 1.05 : (isAppeared ? 1 : (isFastScrolling ? 1 : 0.9)))
        .offset(y: (isAppeared || isFastScrolling) ? 0 : 20)
        .onAppear {
            if isFastScrolling {
                isAppeared = true
                return
            }
            let delay = Double(staggerIndex ?? 0 % 15) * 0.05
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(delay)) {
                isAppeared = true
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
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
                NotificationCenter.default.post(name: .mediaStateChanged, object: nil)
            }
        }
    }

    @ViewBuilder
    private var typeBadge: some View {
        Group {
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
        .background(Color.accentColor.opacity(0.4))
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
                        NotificationCenter.default.post(name: .mediaStateChanged, object: nil)
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
