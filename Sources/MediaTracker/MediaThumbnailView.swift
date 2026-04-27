import SwiftUI
import SwiftData

struct MediaThumbnailView: View {
    enum DisplayMode {
        case hero, grid, search
    }

    // 1. Immutable Captured Snapshot
    private let capturedID: PersistentIdentifier?
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
    
    // 2. Reference Layer (Used only if object is valid)
    let item: MediaItem?
    let metadata: MediaThumbnailMetadata?
    let result: MediaSearchResult?
    
    // 3. Configuration
    let mode: DisplayMode
    var showTypeBadge: Bool = true
    var isUpcomingSection: Bool = false
    var isLocalInSearch: Bool = false
    var action: (() -> Void)? = nil
    var namespace: Namespace.ID? = nil
    var staggerIndex: Int? = nil
    var isFastScrolling: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    @State private var isHovered = false
    @State private var isButtonHovered = false
    @State private var isAppeared = false
    @State private var isRemoved = false

    init(
        item: MediaItem, mode: DisplayMode = .grid, showTypeBadge: Bool = true, isUpcomingSection: Bool = false,
        namespace: Namespace.ID? = nil, staggerIndex: Int? = nil, isFastScrolling: Bool = false, action: (() -> Void)? = nil
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
        self.action = action
        
        // IMMEDIATE CAPTURE - This prevents crashes if item is deleted later
        self.capturedID = item.persistentModelID
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
    }
    
    init(
        metadata: MediaThumbnailMetadata, mode: DisplayMode = .grid, showTypeBadge: Bool = true, isUpcomingSection: Bool = false,
        namespace: Namespace.ID? = nil, staggerIndex: Int? = nil, isFastScrolling: Bool = false, action: (() -> Void)? = nil
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
        self.action = action
        
        self.capturedID = metadata.id
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

    private var nextEpisodeLabel: String? { item?.storedNextEpisodeLabel ?? capturedNextEpisodeLabel }
    private var watchProgress: String? { item?.storedWatchProgressLabel ?? capturedWatchProgress }
    private var isUpcoming: Bool { item?.isUpcoming ?? capturedIsUpcoming }
    private var gridBadgeText: String? { item?.badgeText ?? capturedGridBadgeText }

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
        .contextMenu {
            if !isRemoved, let id = capturedID {
                libraryContextMenu(for: id, type: capturedType, state: capturedState, progress: capturedProgress)
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack(alignment: .center) {
            // 1. Poster Layer
            posterLayer
                .blur(radius: isHovered ? 15 : 0)
            
            if isHovered {
                Rectangle()
                    .fill(.ultraThinMaterial.opacity(0.6))
            }
            
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
            .opacity(isHovered ? 0 : 1) // Hide when hovered to reveal shadow gallery
            
            // 2. SHADOW GALLERY: The Reveal (Centered)
            VStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: mode == .hero ? 18 : 13, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 4)
                
                HStack(spacing: 6) {
                    if let year = yearLabel {
                        Text(year)
                    }
                    
                    // Show stats/progress in the hover stack (But NOT if completed)
                    if safeState != .completed {
                        let currentInfo = nextEpisodeLabel ?? watchProgress
                        if let info = currentInfo {
                            Text("•")
                            Text(info)
                        }
                    }
                }
                .font(.system(size: mode == .hero ? 12 : 10, weight: .bold, design: .rounded))
                .kerning(1.0)
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.6), radius: 2)
                
                // RESTORED DATE ROW
                if isUpcoming, let date = gridBadgeText {
                    Text(date.uppercased())
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .kerning(1.5)
                        .padding(.top, 4)
                        .foregroundStyle(date.contains("STREAMING") ? appAccent.color : .white)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                }
            }
            .padding(.horizontal, 12)
            .opacity(isHovered ? 1 : 0)
            .scaleEffect(isHovered ? 1.0 : 0.9)
            
            // 3. Search Mode (Modal status remains visible)
            if mode == .search {
                searchOverlay
            }
        }
        .frame(width: width, height: height)
        .background {
            if let ns = namespace {
                let itemIDString: String = {
                    if let id = capturedID { return "\(id)" }
                    return "\(result?.id.hashValue ?? 0)"
                }()
                
                if !itemIDString.isEmpty {
                    Color.clear.matchedGeometryEffect(id: "poster_bg_\(itemIDString)", in: ns)
                }
            }
        }
        .cornerRadius(mode == .hero ? 16 : 12)
        .opacity(isAppeared ? 1 : 0)
        .scaleEffect(isHovered ? 1.05 : (isAppeared ? 1 : 0.9))
        .offset(y: isAppeared ? 0 : 10)
        .onAppear {
            let delay = Double(staggerIndex ?? 0 % 20) * 0.04
            withAnimation(.smooth(duration: 0.5).delay(delay)) {
                isAppeared = true
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var posterLayer: some View {
        let content = Group {
            if let urlString = posterURL, let url = URL(string: urlString) {
                let baseColor = (item?.themeColorHex ?? capturedThemeColorHex).flatMap { Color(hex: $0) }
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
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                    .frame(width: width, height: height)
            }
        }

        if let ns = namespace {
            let itemIDString: String = {
                if let id = capturedID { return "\(id)" }
                return "\(result?.id.hashValue ?? 0)"
            }()
            
            if !itemIDString.isEmpty {
                content.matchedGeometryEffect(id: "poster_\(itemIDString)", in: ns)
            } else {
                content
            }
        } else {
            content
        }
    }

    private func markNextEpisodeAsWatched(for item: MediaItem) {
        guard item.modelContext != nil && !item.isDeleted, let tv = item.tvShowDetails else { return }
        let allEpisodes = tv.seasons.sorted { $0.seasonNumber < $1.seasonNumber }
            .flatMap { $0.episodes.sorted { $0.episodeNumber < $1.episodeNumber } }

        if let next = allEpisodes.first(where: { !$0.isWatched }) {
            next.isWatched = true
            item.lastInteractionDate = Date()
            Task { @MainActor in
                item.checkOverallCompletion()
            }
        }
    }

    @ViewBuilder
    private var searchOverlay: some View {
        if isAdded {
            ZStack {
                // Dimming layer only for non-local results to emphasize "In Library"
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
                    // Local result in search - main hover info handles the reveal
                    // but we can add an extra "Open" indicator if we want
                    Rectangle()
                        .fill(.black.opacity(0.2))
                }
            }
        } else if isHovered {
            // New Web Result - Show "Add" UI that doesn't cover center
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

    @ViewBuilder
    private var typeBadge: some View {
        Group {
            switch type {
            case .movie: Image(systemName: "film")
            case .tvShow: Image(systemName: "tv")
            }
        }
        .font(.system(size: 9, weight: .bold))
        .liquidGlassPill(accentColor: appAccent.color, isSolid: false)
    }

    @ViewBuilder
    private func libraryContextMenu(for itemID: PersistentIdentifier, type: MediaType, state: MediaState, progress: Double?) -> some View {
        Section("Quick Actions") {
            if type == .tvShow {
                Button {
                    if let item = modelContext.model(for: itemID) as? MediaItem, !item.isDeleted {
                        markNextEpisodeAsWatched(for: item)
                    }
                } label: {
                    Label("Mark Next Episode Watched", systemImage: "play.fill")
                }
            }
            
            if state != .completed {
                Button {
                    if let item = modelContext.model(for: itemID) as? MediaItem, !item.isDeleted {
                        withAnimation {
                            item.state = .completed
                            item.lastUpdated = Date()
                            item.lastInteractionDate = Date()
                        }
                    }
                } label: {
                    Label("Quick Complete", systemImage: "checkmark.seal.fill")
                }
            }
        }
        
        Section("Status") {
            ForEach(MediaItem.availableStates(for: type, progress: progress), id: \.self) { targetState in
                Button(targetState.displayName) {
                    if let item = modelContext.model(for: itemID) as? MediaItem, !item.isDeleted {
                        withAnimation {
                            item.state = targetState
                            item.lastUpdated = Date()
                            item.lastInteractionDate = Date()
                            item.lastStateChangeDate = Date()
                        }
                    }
                }
            }
        }
        Divider()
        Button(role: .destructive) {
            withAnimation {
                isRemoved = true
                FeedbackManager.shared.trigger(.removeFromLibrary)
            }
            
            if let item = modelContext.model(for: itemID) as? MediaItem, !item.isDeleted {
                let id = item.id
                NotificationManager.shared.cancelNotification(id: id, type: type)
                modelContext.delete(item)
                NotificationCenter.default.post(name: .mediaStateChanged, object: nil)
            }
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }
}

struct MediaThumbnailPlaceholder: View {
    let mode: MediaThumbnailView.DisplayMode
    @Environment(\.colorScheme) var colorScheme
    
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
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: mode == .hero ? 16 : 12)
                .fill(Color.secondary.opacity(colorScheme == .dark ? 0.2 : 0.15))
                .overlay {
                    RoundedRectangle(cornerRadius: mode == .hero ? 16 : 12)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                }
            
            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 12)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .frame(width: width, height: height)
    }
}
