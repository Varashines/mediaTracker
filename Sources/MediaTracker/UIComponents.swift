import SwiftUI

struct StatusBadgePrimitive: View {
    let label: String
    let systemImage: String
    let accentColor: Color
    let isSolid: Bool
    let progress: Double?
    var isCompact: Bool = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: isCompact ? 0 : 4) {
            Image(systemName: systemImage)
                .font(.system(size: isCompact ? 11 : 10, weight: .bold))
            
            if !isCompact {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
            }
        }
        .liquidGlassPill(accentColor: accentColor, isSolid: isSolid, progress: progress)
    }
}

struct LiquidGlassModifier: ViewModifier {
    let accentColor: Color
    let isSolid: Bool
    let foregroundColor: Color?
    let progress: Double?
    @Environment(\.colorScheme) var colorScheme

    init(accentColor: Color, isSolid: Bool = false, foregroundColor: Color? = nil, progress: Double? = nil) {
        self.accentColor = accentColor
        self.isSolid = isSolid
        self.foregroundColor = foregroundColor
        self.progress = progress
    }

    func body(content: Content) -> some View {
        let isLight = accentColor.isLightColor
        let isAsleep = SleepManager.shared.isAsleep

        // If solid, always white. If frosted, use primary (adaptive black/white).
        let defaultForeground = isSolid ? Color.white : .primary
        let foreground = foregroundColor ?? defaultForeground

        // If solid, high opacity. If frosted, subtle tint.
        let tintOpacity = isSolid ? 1.0 : (isLight ? 0.35 : 0.5)

        return
            content
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background {
                if isAsleep {
                    // FLAT BACKGROUND DURING SLEEP
                    Capsule()
                        .fill(isSolid ? accentColor : Color.gray.opacity(0.2))
                } else {
                    ZStack(alignment: .leading) {
                        if isSolid {
                            Capsule()
                                .fill(accentColor.opacity(tintOpacity))
                        } else {
                            ZStack {
                                Capsule()
                                    .fill(.ultraThickMaterial)
                                Capsule()
                                    .fill(accentColor.opacity(tintOpacity))
                            }
                        }

                        // Glow & Fill Progress
                        if let progress = progress {
                            GeometryReader { geo in
                                Capsule()
                                    .fill(foreground.opacity(0.15))
                                    .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
                            }
                        }
                    }
                }
            }
            .clipShape(Capsule())
            .overlay {
                // Subtle stroke for definition
                if !isAsleep {
                    Capsule()
                        .stroke(
                            accentColor.opacity(isSolid ? 1.0 : (isLight ? 0.7 : 0.5)), lineWidth: 0.5)
                }
            }
            .overlay(alignment: .bottom) {
                // Glowing bottom line for progress
                if let progress = progress, !isAsleep {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            Capsule()
                                .fill(foreground.opacity(0.8))
                                .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)), height: 1.5)
                                .shadow(color: foreground.opacity(0.5), radius: 2, x: 0, y: 0)
                                .padding(.horizontal, 4)
                                .padding(.bottom, 1)
                        }
                    }
                }
            }
    }
}

extension View {
    func liquidGlassPill(accentColor: Color, isSolid: Bool = false, foregroundColor: Color? = nil, progress: Double? = nil)
        -> some View
    {
        self.modifier(
            LiquidGlassModifier(
                accentColor: accentColor, isSolid: isSolid, foregroundColor: foregroundColor, progress: progress))
    }
}

// MARK: - Smart Badge View
struct SmartBadgeView: View {
    let item: MediaItem?
    let metadata: MediaThumbnailMetadata?
    let result: MediaSearchResult?
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic

    init(item: MediaItem) {
        self.item = item
        self.metadata = nil
        self.result = nil
    }
    
    init(metadata: MediaThumbnailMetadata) {
        self.item = nil
        self.metadata = metadata
        self.result = nil
    }

    init(result: MediaSearchResult) {
        self.item = nil
        self.metadata = nil
        self.result = result
    }

    var body: some View {
        if let metadata = metadata {
            if let label = metadata.smartBadgeLabel, let icon = metadata.smartBadgeIcon {
                intelligentBadge(label: label, icon: icon, isSparkle: metadata.isSparkleBadge)
            } else {
                statusUI(
                    isUpcoming: metadata.isUpcoming,
                    state: metadata.state,
                    badgeText: metadata.badgeText,
                    watchProgressLabel: metadata.watchProgress,
                    nextEpisodeLabel: metadata.nextEpisodeToWatchLabel,
                    progress: metadata.progress
                )
            }
        } else if let item = item, item.modelContext != nil {
            if let label = item.storedSmartBadgeLabel, let icon = item.storedSmartBadgeIcon {
                intelligentBadge(label: label, icon: icon, isSparkle: item.storedSmartBadgeIsSparkle)
            } else {
                statusUI(
                    isUpcoming: item.storedIsUpcoming,
                    state: item.state,
                    badgeText: item.gridBadgeText,
                    watchProgressLabel: item.storedWatchProgressLabel,
                    nextEpisodeLabel: item.storedNextEpisodeLabel,
                    progress: item.storedProgress
                )
            }
        } else if result != nil {
             statusUI(isUpcoming: false, state: .wishlist, badgeText: nil, watchProgressLabel: nil, nextEpisodeLabel: nil, progress: nil)
        }
    }

    @ViewBuilder
    private func intelligentBadge(label: String, icon: String, isSparkle: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.system(size: 9, weight: .black))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSparkle ? appAccent.color.gradient : Color.secondary.opacity(0.8).gradient)
        .foregroundStyle(.white)
        .cornerRadius(6)
        .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
    }

    @ViewBuilder
    private func statusUI(
        isUpcoming: Bool,
        state: MediaState?,
        badgeText: String?,
        watchProgressLabel: String?,
        nextEpisodeLabel: String?,
        progress: Double?
    ) -> some View {
        let currentState = state ?? .wishlist

        if currentState == .completed {
            EmptyView()
        } else {
            // 1. Determine Availability
            let badge = badgeText ?? ""
            let isAvailable = isUpcoming && (badge.contains("Streaming") || badge.contains("Available"))

            // 2. Determine Display Label
            let displayLabel = (isUpcoming ? nextEpisodeLabel : watchProgressLabel) ?? currentState.displayName

            // 3. Determine Icon
            let icon = isAvailable ? "play.fill" : (isUpcoming ? "sparkles" : currentState.iconName)

            // 4. Pill Logic
            let isInProgress = (currentState == .active || currentState == .rewatching)
            let hasEpisodeStats = nextEpisodeLabel != nil
            let showFullPill = (isUpcoming && hasEpisodeStats) || (!isUpcoming && isInProgress)

            // 5. Progress Bar
            let showProgressBar = !isUpcoming && isInProgress

            StatusBadgePrimitive(
                label: displayLabel,
                systemImage: icon,
                accentColor: isAvailable ? appAccent.color : .primary,
                isSolid: isAvailable,
                progress: showProgressBar ? progress : nil,
                isCompact: !showFullPill
            )
        }
    }

}

// MARK: - Unified Media Thumbnail View
struct MediaThumbnailView: View {
    enum DisplayMode {
        case hero, grid, search
    }

    let item: MediaItem?
    let metadata: MediaThumbnailMetadata?
    let result: MediaSearchResult?
    let mode: DisplayMode
    var showTypeBadge: Bool = true
    var isUpcomingSection: Bool = false
    var isLocalInSearch: Bool = false
    var action: (() -> Void)? = nil
    var namespace: Namespace.ID? = nil
    var staggerIndex: Int? = nil
    var isFastScrolling: Bool = false // NEW: Support for velocity-aware rendering

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    @State private var isHovered = false
    @State private var isButtonHovered = false
    @State private var isAppeared = false

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

    private var title: String {
        if let item = item, item.modelContext != nil {
            return item.title
        }
        return metadata?.title ?? result?.title ?? ""
    }

    private var posterURL: String? {
        if let item = item, item.modelContext != nil {
            return item.posterURL
        }
        return metadata?.posterURL ?? result?.posterURL
    }

    private var type: MediaType {
        if let item = item, item.modelContext != nil {
            return item.type ?? .movie
        }
        return metadata?.type ?? result?.type ?? .movie
    }

    private var yearLabel: String? {
        if let item = item, item.modelContext != nil {
            if let date = item.releaseDate {
                return Calendar.current.dateComponents([.year], from: date).year.map { String($0) }
            }
        } else if let metadata = metadata {
            if let date = metadata.releaseDate {
                return Calendar.current.dateComponents([.year], from: date).year.map { String($0) }
            }
        } else if let dateString = result?.releaseDate, dateString.count >= 4 {
            return String(dateString.prefix(4))
        }
        return nil
    }

    private var isAdded: Bool {
        if let item = item {
            return item.modelContext != nil
        }
        return metadata != nil || isLocalInSearch
    }

    var body: some View {
        Group {
            if let action = action {
                Button(action: action) {
                    mainContent
                }
                .buttonStyle(.plain)
            } else {
                mainContent
            }
        }
        .contextMenu {
            if let item = item, item.modelContext != nil {
                libraryContextMenu(for: item)
            } else if let metadata = metadata, let item = modelContext.model(for: metadata.id) as? MediaItem, item.modelContext != nil {
                libraryContextMenu(for: item)
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
                    let currentState = (item?.modelContext != nil ? item?.state : metadata?.state) ?? .wishlist
                    if currentState != .completed {
                        let stats = (item?.modelContext != nil ? item?.storedNextEpisodeLabel : metadata?.nextEpisodeToWatchLabel)
                        let progress = (item?.modelContext != nil ? item?.watchProgressLabel : metadata?.watchProgress)
                        let currentInfo = (item?.calculateIsUpcoming ?? metadata?.isUpcoming ?? false) ? stats : progress
                        
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
                if (item?.calculateIsUpcoming ?? metadata?.isUpcoming ?? false), 
                   let date = (item?.modelContext != nil ? item?.gridBadgeText : metadata?.badgeText) {
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
            
            // 4. Compact state icons at bottom (Even without hover)
            if !isHovered {
                VStack {
                    Spacer()
                    let state = (item?.modelContext != nil ? item?.state : metadata?.state) ?? .wishlist
                    let upcoming = (item?.calculateIsUpcoming ?? metadata?.isUpcoming ?? false)
                    
                    if upcoming {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(appAccent.color)
                            .shadow(color: appAccent.color.opacity(0.6), radius: 3)
                            .padding(.bottom, 8)
                    } else if state == .completed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(appAccent.color)
                            .shadow(color: appAccent.color.opacity(0.4), radius: 3)
                            .padding(.bottom, 8)
                    } else if state != .active && state != .rewatching {
                        Image(systemName: state.iconName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.bottom, 8)
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .background {
            if let ns = namespace {
                let itemIDString: String = {
                    if let item = item, item.modelContext != nil { return "\(item.id)" }
                    if let metadata = metadata { return "\(metadata.id)" }
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
                let colorString = (item?.modelContext != nil ? item?.themeColorHex : metadata?.themeColorHex)
                let baseColor = colorString.flatMap { Color(hex: $0) }
                
                // Request slightly more pixels (3x) to ensure crispness even on high-end Retina screens
                CachedImage(url: url, targetSize: CGSize(width: width * 3, height: height * 3), themeColor: baseColor, isFastScrolling: isFastScrolling) {
                    _ in
                } placeholder: {
                    Rectangle().fill(Color.secondary.opacity(0.1))
                        .shimmer()
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
                if let item = item, item.modelContext != nil { return "\(item.id)" }
                if let metadata = metadata { return "\(metadata.id)" }
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

    @ViewBuilder
    private func quickWatchOverlay(for item: MediaItem) -> some View {
        Button {
            markNextEpisodeAsWatched(for: item)
        } label: {
            HStack(spacing: 6) {
                if isButtonHovered, let nextLabel = item.nextEpisodeToWatchLabel {
                    Text(nextLabel)
                        .font(.system(size: 8, weight: .bold))
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity))
                }

                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.1), radius: 2)
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.3), lineWidth: 0.5)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isButtonHovered = hovering
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private func markNextEpisodeAsWatched(for item: MediaItem) {
        guard let tv = item.tvShowDetails else { return }
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
                Rectangle()
                    .fill(.black.opacity(isLocalInSearch ? (isHovered ? 0.2 : 0.05) : 0.6))

                if !isLocalInSearch {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.green)
                        Text("In Library")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                } else if isHovered {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                        Text("Open")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    }
                    .padding(8)
                    .background(.black.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        } else if isHovered {
            ZStack {
                Rectangle().fill(.black.opacity(0.3))
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
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
    private func libraryContextMenu(for item: MediaItem) -> some View {
        Section("Quick Actions") {
            if item.type == .tvShow {
                Button {
                    markNextEpisodeAsWatched(for: item)
                } label: {
                    Label("Mark Next Episode Watched", systemImage: "play.fill")
                }
            }
            
            if item.state != .completed {
                Button {
                    withAnimation {
                        item.state = .completed
                        item.lastUpdated = Date()
                        item.lastInteractionDate = Date()
                    }
                } label: {
                    Label("Quick Complete", systemImage: "checkmark.seal.fill")
                }
            }
        }
        
        Section("Status") {
            ForEach(availableStates(for: item), id: \.self) { state in
                Button(state.displayName) {
                    withAnimation {
                        item.state = state
                        item.lastUpdated = Date()
                        item.lastInteractionDate = Date()
                        item.lastStateChangeDate = Date()
                    }
                }
            }
        }
        Divider()
        Button(role: .destructive) {
            NotificationManager.shared.cancelNotification(id: item.id, type: item.type ?? .movie)
            modelContext.delete(item)
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    private func availableStates(for item: MediaItem) -> [MediaState] {
        item.availableStates
    }
}

// MARK: - Taste Controls
struct TasteToggle: View {
    @Bindable var item: MediaItem
    let themeColor: Color
    
    var body: some View {
        HStack(spacing: 12) {
            TastePill(
                label: "Love",
                icon: "heart",
                isSelected: item.tasteValue == "Love",
                activeColor: .red,
                action: { setTaste("Love") }
            )
            
            TastePill(
                label: "Like",
                icon: "hand.thumbsup",
                isSelected: item.tasteValue == "Like",
                activeColor: .blue,
                action: { setTaste("Like") }
            )
            
            TastePill(
                label: "Dislike",
                icon: "hand.thumbsdown",
                isSelected: item.tasteValue == "Dislike",
                activeColor: .gray,
                action: { setTaste("Dislike") }
            )
        }
    }
    
    private func setTaste(_ val: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if item.tasteValue == val {
                item.tasteValue = "None"
            } else {
                item.tasteValue = val
            }
        }
    }
}

struct TastePill: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let activeColor: Color
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "\(icon).fill" : icon)
                Text(label)
            }
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : .primary.opacity(0.8))
            .background {
                if isSelected {
                    activeColor
                } else {
                    Color.primary.opacity(0.05)
                        .background(.ultraThinMaterial)
                }
            }
            .clipShape(Capsule())
            .shadow(color: isSelected ? activeColor.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

struct HomeHeroCard: View {
    let metadata: MediaThumbnailMetadata
    let item: MediaItem?
    let namespace: Namespace.ID
    var isFastScrolling: Bool = false
    @State private var isHovered = false
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ZStack(alignment: .leading) {
            // 1. Cinematic Backdrop (Blurred & Darkened)
            if let backdrop = metadata.backdropURL, let url = URL(string: backdrop) {
                CachedImage(url: url, targetSize: CGSize(width: 1500, height: 840), isFastScrolling: isFastScrolling) { _ in } placeholder: {
                    Rectangle().fill(Color.secondary.opacity(0.1))
                        .shimmer()
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 500, height: 280)
                .clipped()
                .blur(radius: isHovered ? 20 : 12)
                .overlay(Color.black.opacity(isHovered ? 0.6 : 0.45))
            } else {
                Rectangle().fill(Color.black.opacity(0.8))
                    .frame(width: 500, height: 280)
            }
            
            // 2. Matching Your Taste Tag (Top Right)
            if let context = recommendationContext {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 10, weight: .black))
                            Text(context.uppercased())
                                .font(.system(size: 9, weight: .black))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(.white)
                        .background(.ultraThinMaterial.opacity(0.8))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5)
                        }
                        .padding(20)
                    }
                    Spacer()
                }
            }
            
            HStack(spacing: 24) {
                // 3. Floating Vertical Poster (3D Depth)
                if let poster = metadata.posterURL, let url = URL(string: poster) {
                    CachedImage(url: url, targetSize: CGSize(width: 300, height: 450), isFastScrolling: isFastScrolling) { _ in } placeholder: {
                        Rectangle().fill(Color.secondary.opacity(0.1))
                            .shimmer()
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 140, height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 10)
                }
                
                // 4. Immersive Details (Right Side)
                VStack(alignment: .leading, spacing: 6) {
                    if metadata.isUpcoming {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.yellow)
                            .padding(.bottom, 2)
                    }
                    
                    Text(metadata.title)
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                    
                    Text(metadata.formattedMetadata)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.trailing, 20)
                
                Spacer()
            }
            .padding(.leading, 30)
        }
        .frame(width: 500, height: 280)
        .cornerRadius(24)
        .shadow(color: .black.opacity(isHovered ? 0.3 : 0), radius: 20, x: 0, y: 10)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
    }
    
    private var recommendationContext: String? {
        // Priority 0: Explicit Recommendation Reason from Taste Engine
        if let reason = metadata.recommendationReason {
            return reason
        }

        guard let item = item else { return nil }
        
        // Priority 1: Creators/Directors
        let creators = (item.movieDetails?.creators ?? item.tvShowDetails?.creators) ?? []
        if let firstCreator = creators.first {
            return "\(item.type == .movie ? "Directed by" : "Created by") \(firstCreator)"
        }
        
        // Priority 2: Leading Cast
        let cast = (item.movieDetails?.cast ?? item.tvShowDetails?.cast) ?? []
        if let firstActor = cast.sorted(by: { $0.order < $1.order }).first {
            return "Starring \(firstActor.name)"
        }
        
        // Priority 3: Primary Genre
        if let firstGenre = metadata.genres.first {
            return "\(firstGenre) Selection"
        }
        
        return "Picked for you"
    }
}

// MARK: - Library Empty State View
struct LibraryEmptyStateView: View {
    let category: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(description)
        }
        .frame(maxHeight: .infinity)
        .padding(.top, 100)
    }

    private var title: String {
        switch category {
        case "Upcoming": return "Nothing Upcoming"
        case "InProgress": return "Nothing in Progress"
        case "Watchlist": return "Watchlist is Empty"
        case "Loved": return "No Loved Items"
        case "Completed": return "Nothing Completed"
        case "OnHold": return "Nothing on Hold"
        case "Dropped": return "No Dropped Items"
        case "Rewatching": return "Not Re-watching Anything"
        case "Disliked": return "No Disliked Items"
        default: return "Library is Empty"
        }
    }

    private var icon: String {
        switch category {
        case "Upcoming": return "calendar.badge.clock"
        case "InProgress": return "play.slash"
        case "Watchlist": return "list.bullet.rectangle"
        case "Loved": return "heart.fill"
        case "Completed": return "checkmark.circle.fill"
        case "OnHold": return "pause.circle"
        case "Dropped": return "xmark.bin"
        case "Rewatching": return "arrow.clockwise.circle"
        case "Disliked": return "hand.thumbsdown.fill"
        default: return "tray"
        }
    }

    private var description: String {
        switch category {
        case "Upcoming": return "No releases or new episodes are expected soon."
        case "InProgress": return "You're all caught up! Start something new from your watchlist."
        case "Watchlist": return "Your watchlist is empty. Search for something to add!"
        case "Loved": return "Items you've loved will appear here."
        case "Completed": return "All your finished movies and series will be collected here."
        case "OnHold": return "Items you've paused will appear here."
        case "Dropped": return "Items you've decided not to finish."
        case "Rewatching": return "Everything you decide to experience again will live here."
        case "Disliked": return "Items you've actively disliked."
        default: return "Start building your collection by searching for movies or shows."
        }
    }
}

extension Color {
    static let detailAccent = Color.blue

    static func semanticGreen(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color.green
        } else {
            return Color(red: 0.0, green: 0.6, blue: 0.2)
        }
    }

    static func semanticRed(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color.red
        } else {
            return Color(red: 0.75, green: 0.1, blue: 0.1)
        }
    }

    var isLightColor: Bool {
        guard let rgbColor = NSColor(self).usingColorSpace(.sRGB) else { return false }
        var r: CGFloat
        var g: CGFloat
        var b: CGFloat
        var a: CGFloat
        (r, g, b, a) = (0, 0, 0, 0)
        rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.5
    }

    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        guard let rgbColor = NSColor(self).usingColorSpace(.sRGB) else {
            return "000000"
        }
        let r = Float(rgbColor.redComponent)
        let g = Float(rgbColor.greenComponent)
        let b = Float(rgbColor.blueComponent)
        return String(
            format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }

    static func randomVibrant(for colorScheme: ColorScheme) -> Color {
        let hues: [Double] = [0.0, 0.1, 0.15, 0.45, 0.55, 0.65, 0.75, 0.85]
        let randomHue = hues.randomElement() ?? 0.5
        let saturation: Double = colorScheme == .dark ? 0.25 : 0.35
        let brightness: Double = colorScheme == .dark ? 0.95 : 0.8
        return Color(hue: randomHue, saturation: saturation, brightness: brightness)
    }
}

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: colorScheme == .dark ? .white.opacity(0.15) : .white.opacity(0.5), location: 0.5),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .rotationEffect(.degrees(30))
                    .frame(width: geo.size.width * 3)
                    .offset(x: -geo.size.width * 1.5 + (geo.size.width * 3 * phase))
                }
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}

struct ThemeBackground: ViewModifier {
    var networkOverride: String? = nil
    var tintOverride: Color? = nil
    var activeCategory: String? = nil
    var disableBrandBackground: Bool = false
    @AppStorage("theme_style") private var themeStyle: ThemeStyle = .standard
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        let isAsleep = SleepManager.shared.isAsleep
        let isDiscover = activeCategory == "Discover" || activeCategory == "DiscoverBeta"
        
        content
            .background {
                ZStack {
                    if isAsleep {
                        Color(NSColor.windowBackgroundColor)
                    } else {
                        if themeStyle == .brand && !disableBrandBackground {
                            appAccent.brandBackground(for: colorScheme)
                        } else {
                            Color(NSColor.windowBackgroundColor)
                        }

                        if let tint = tintOverride {
                            tint.opacity(colorScheme == .dark ? 0.35 : 0.25)
                        } else if let network = networkOverride,
                            let color = NetworkThemeManager.shared.color(for: network)
                        {
                            color.opacity(colorScheme == .dark ? 0.35 : 0.25)
                        }
                        
                        // Phase 2 Optimization: Metal-Accelerated Ambience
                        TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                            Color.clear
                                .colorEffect(
                                    ShaderLibrary.backgroundGlow(
                                        .float2(NSScreen.main?.frame.size ?? .zero),
                                        .float(timeline.date.timeIntervalSinceReferenceDate),
                                        .float(isDiscover ? 1.0 : 0.0)
                                    )
                                )
                        }
                    }
                }
                .ignoresSafeArea()
            }
    }
}

extension View {
    func appBackground(network: String? = nil, category: String? = nil, tint: Color? = nil, disableBrandBackground: Bool = false) -> some View {
        self.modifier(ThemeBackground(networkOverride: network, tintOverride: tint, activeCategory: category, disableBrandBackground: disableBrandBackground))
    }
}

@MainActor
@Observable
class NetworkThemeManager {
    static let shared = NetworkThemeManager()
    private let storageKey = "cached_network_themes"
    var themeMap: [String: String] = [:]
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.themeMap = decoded
        }
    }
    
    func color(for network: String) -> Color? {
        guard let hex = themeMap[network] else { return nil }
        return Color(hex: hex)
    }
    
    func save(color: Color, for network: String) {
        let hex = color.toHex()
        themeMap[network] = hex
        saveToDisk()
    }
    
    func resetAll() {
        themeMap.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
    
    private func saveToDisk() {
        if let encoded = try? JSONEncoder().encode(themeMap) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}

// MARK: - Hero Carousel with Progress Indicator

@preconcurrency
struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct HeroCarousel: View {
    let title: String
    let icon: String
    let iconColor: Color
    let recommendations: [MediaThumbnailMetadata]
    let namespace: Namespace.ID
    var isFastScrolling: Bool = false
    @Environment(\.modelContext) private var modelContext
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    
    @State private var scrollProgress: Double = 0
    @State private var scrollSpace = UUID().uuidString
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with Integrated Progress Bar
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                Text(title)
                
                Spacer()
                
                if recommendations.count > 1 {
                    GeometryReader { geo in
                        let availableWidth = geo.size.width
                        let itemWidth = max(40, min(availableWidth, availableWidth * 0.3)) // Proportional pill
                        let scrollableTrackWidth = availableWidth - itemWidth
                        
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.15))
                                .background(Capsule().fill(.ultraThinMaterial))
                                .frame(height: 4)
                            
                            Capsule()
                                .fill(appAccent.color.gradient)
                                .frame(width: itemWidth, height: 4)
                                .offset(x: scrollProgress * scrollableTrackWidth)
                                .shadow(color: appAccent.color.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .frame(maxHeight: .infinity, alignment: .center) // Center vertically in HStack
                    }
                    .frame(width: 150, height: 4) // Fixed width for the progress bar itself
                    .padding(.trailing, 10)
                }
            }
            .font(.system(size: 28, weight: .black))
            .padding(.horizontal, 40)
            .padding(.bottom, 8)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(Array(recommendations.enumerated()), id: \.offset) { index, metadata in
                        if let item = modelContext.model(for: metadata.id) as? MediaItem {
                            NavigationLink(value: item) {
                                HomeHeroCard(metadata: metadata, item: item, namespace: namespace, isFastScrolling: isFastScrolling)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 20)
                .background(
                    GeometryReader { geo in
                        let minX = geo.frame(in: .named(scrollSpace)).minX
                        Color.clear
                            .preference(key: ScrollOffsetKey.self, value: [scrollSpace: minX])
                            .onAppear { contentWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, newValue in contentWidth = newValue }
                    }
                )
            }
            .coordinateSpace(name: scrollSpace)
            .frame(height: 320) // Constrain height to prevent greedy vertical expansion
            .scrollClipDisabled()
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { containerWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, newValue in containerWidth = newValue }
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { dict in
                guard let minX = dict[scrollSpace] else { return }
                let maxScroll = max(1, contentWidth - containerWidth)
                let currentScroll = max(0, -minX)
                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                    scrollProgress = min(1.0, currentScroll / maxScroll)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true) // Ensure the carousel doesn't push elements away
    }
}

// MARK: - Shelf Carousel (For Secondary Sections)

struct ShelfCarousel: View {
    let title: String
    let icon: String
    let iconColor: Color
    let items: [MediaThumbnailMetadata]
    let namespace: Namespace.ID
    var isFastScrolling: Bool = false
    @Environment(\.modelContext) private var modelContext
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    
    @State private var scrollProgress: Double = 0
    @State private var scrollSpace = UUID().uuidString
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with Integrated Progress Bar
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                Text(title)
                
                Spacer()
                
                if items.count > 1 {
                    GeometryReader { geo in
                        let availableWidth = geo.size.width
                        let itemWidth = max(40, min(availableWidth, availableWidth * 0.2)) // Proportional pill
                        let scrollableTrackWidth = availableWidth - itemWidth
                        
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.1))
                                .background(Capsule().fill(.ultraThinMaterial))
                                .frame(height: 3)
                            
                            Capsule()
                                .fill(appAccent.color.gradient)
                                .frame(width: itemWidth, height: 3)
                                .offset(x: scrollProgress * scrollableTrackWidth)
                                .shadow(color: appAccent.color.opacity(0.3), radius: 2, x: 0, y: 1)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(width: 120, height: 3) // Fixed width for the progress bar itself
                    .padding(.trailing, 20)
                }
            }
            .font(.system(size: 28, weight: .black))
            .padding(.horizontal, 40)
            .padding(.bottom, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(items) { metadata in
                        if let item = modelContext.model(for: metadata.id) as? MediaItem {
                            NavigationLink(value: item) {
                                MediaThumbnailView(metadata: metadata, mode: .grid, namespace: namespace, isFastScrolling: isFastScrolling)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 12)
                .background(
                    GeometryReader { geo in
                        let minX = geo.frame(in: .named(scrollSpace)).minX
                        Color.clear
                            .preference(key: ScrollOffsetKey.self, value: [scrollSpace: minX])
                            .onAppear { contentWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, newValue in contentWidth = newValue }
                    }
                )
            }
            .coordinateSpace(name: scrollSpace)
            .frame(height: 270) // Fixed height for 160x240 grid cards + padding
            .scrollClipDisabled()
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { containerWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, newValue in containerWidth = newValue }
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { dict in
                guard let minX = dict[scrollSpace] else { return }
                let maxScroll = max(1, contentWidth - containerWidth)
                let currentScroll = max(0, -minX)
                withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                    scrollProgress = min(1.0, currentScroll / maxScroll)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
