import SwiftUI

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

// MARK: - Status Badge View
struct StatusBadgeView: View {
    let item: MediaItem?
    let metadata: MediaThumbnailMetadata?
    let result: MediaSearchResult?

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
        if let item = item {
            itemStatusBadge(item)
        } else if let metadata = metadata {
            metadataStatusBadge(metadata)
        } else if let result = result {
            resultStatusBadge(result)
        }
    }

    @ViewBuilder
    private func itemStatusBadge(_ item: MediaItem) -> some View {
        statusUI(isUpcoming: item.isUpcoming, state: item.state, watchProgressLabel: item.watchProgressLabel, progress: item.progress)
    }

    @ViewBuilder
    private func metadataStatusBadge(_ m: MediaThumbnailMetadata) -> some View {
        statusUI(isUpcoming: m.isUpcoming, state: m.state, watchProgressLabel: m.watchProgress, progress: m.progress)
    }

    @ViewBuilder
    private func statusUI(isUpcoming: Bool, state: MediaState?, watchProgressLabel: String?, progress: Double?) -> some View {
        Group {
            if isUpcoming {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                    .liquidGlassPill(accentColor: .primary, isSolid: false)
            } else if state == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)
                    .liquidGlassPill(accentColor: .green, isSolid: true)
            } else if state == .active || state == .rewatching {
                HStack(spacing: 2) {
                    Image(
                        systemName: state == .rewatching
                            ? "arrow.clockwise" : "play.circle.fill")
                    if let label = watchProgressLabel {
                        Text(label)
                    }
                }
                .foregroundStyle(.white)
                .liquidGlassPill(
                    accentColor: state == .rewatching ? .orange : .indigo, 
                    isSolid: true,
                    progress: progress
                )
            }
 else if state == .onHold {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.white)
                    .liquidGlassPill(
                        accentColor: Color(red: 0.9, green: 0.5, blue: 0.0), isSolid: true)  // Amber
            } else if state == .dropped {
                Image(systemName: "xmark.bin.fill")
                    .foregroundStyle(.white)
                    .liquidGlassPill(
                        accentColor: Color(red: 0.8, green: 0.2, blue: 0.2), isSolid: true)  // Muted Red
            } else if state == .wishlist && !isUpcoming {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.white)
                    .liquidGlassPill(accentColor: .orange, isSolid: true)
            }
        }
        .font(.system(size: 9, weight: .bold))
    }

    @ViewBuilder
    private func resultStatusBadge(_ result: MediaSearchResult) -> some View {
        // Results only show type badge since they aren't in the library yet
        Group {
            switch result.type {
            case .movie: Image(systemName: "film")
            case .tvShow: Image(systemName: "tv")
            }
        }
        .font(.system(size: 9, weight: .bold))
        .liquidGlassPill(accentColor: .accentColor, isSolid: false)
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

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("app_accent") private var appAccent: AppAccent = .indigo
    @State private var isHovered = false
    @State private var isButtonHovered = false

    init(
        item: MediaItem, mode: DisplayMode = .grid, showTypeBadge: Bool = true, isUpcomingSection: Bool = false,
        namespace: Namespace.ID? = nil, action: (() -> Void)? = nil
    ) {
        self.item = item
        self.metadata = nil
        self.result = nil
        self.mode = mode
        self.showTypeBadge = showTypeBadge
        self.isUpcomingSection = isUpcomingSection
        self.namespace = namespace
        self.action = action
    }
    
    init(
        metadata: MediaThumbnailMetadata, mode: DisplayMode = .grid, showTypeBadge: Bool = true, isUpcomingSection: Bool = false,
        namespace: Namespace.ID? = nil, action: (() -> Void)? = nil
    ) {
        self.item = nil
        self.metadata = metadata
        self.result = nil
        self.mode = mode
        self.showTypeBadge = showTypeBadge
        self.isUpcomingSection = isUpcomingSection
        self.namespace = namespace
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
        item?.title ?? metadata?.title ?? result?.title ?? ""
    }

    private var posterURL: String? {
        item?.posterURL ?? metadata?.posterURL ?? result?.posterURL
    }

    private var type: MediaType {
        item?.type ?? metadata?.type ?? result?.type ?? .movie
    }

    private var yearLabel: String? {
        if let date = item?.releaseDate ?? metadata?.releaseDate {
            return Calendar.current.dateComponents([.year], from: date).year.map { String($0) }
        } else if let dateString = result?.releaseDate, dateString.count >= 4 {
            return String(dateString.prefix(4))
        }
        return nil
    }

    private var isAdded: Bool {
        item != nil || metadata != nil || isLocalInSearch
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
            if let item = item {
                libraryContextMenu(for: item)
            } else if let metadata = metadata, let item = modelContext.model(for: metadata.id) as? MediaItem {
                libraryContextMenu(for: item)
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .top) {
                // 1. Poster Layer
                posterLayer

                // 2. Status/Hover Overlay (Search Mode)
                if mode == .search {
                    searchOverlay
                }

                // 3. Top Section (Always show Film/TV top left, Status Badge top right)
                HStack(alignment: .top) {
                    if showTypeBadge {
                        typeBadge
                    }
                    Spacer()
                    
                    let badge = Group {
                        if let m = metadata {
                            StatusBadgeView(metadata: m)
                        } else if let item = item {
                            StatusBadgeView(item: item)
                        }
                    }
                    
                    if let ns = namespace {
                        let geomID = item?.id ?? "\(metadata?.id.hashValue ?? 0)"
                        badge.matchedGeometryEffect(id: "badge_\(geomID)", in: ns)
                    } else {
                        badge
                    }
                }
                .padding(6)

                // 5. Info Pill (Bottom Center)
                if let m = metadata {
                    VStack {
                        Spacer()
                        infoRowMetadata(for: m)
                            .padding(6)
                    }
                } else if let item = item {
                    VStack {
                        Spacer()
                        infoRow(for: item)
                            .padding(6)
                    }
                }
            }
            .frame(width: width, height: height)
            .background {
                if let ns = namespace {
                    let geomID = item?.id ?? "\(metadata?.id.hashValue ?? 0)"
                    if !geomID.isEmpty {
                        Color.clear.matchedGeometryEffect(id: "poster_bg_\(geomID)", in: ns)
                    }
                }
            }
            .cornerRadius(mode == .hero ? 16 : 12)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.2), value: isHovered)
// 6. Info Section (Below)
VStack(alignment: .leading, spacing: 1) {
    let titleView = Text(title)
        .font(.system(size: mode == .hero ? 15 : 13, weight: .bold))
        .foregroundStyle(.primary)
        .lineLimit(2)
        .multilineTextAlignment(.leading)

    if let ns = namespace {
        let geomID = item?.id ?? "\(metadata?.id.hashValue ?? 0)"
        titleView.matchedGeometryEffect(id: "title_\(geomID)", in: ns)
    } else {
        titleView
    }

    if mode == .search {
        HStack(spacing: 4) {
            if let year = yearLabel {
                Text(year)
            }

            Text("•")

            if type == .tvShow {
                if let network = item?.cachedNetwork ?? metadata?.cachedNetwork {
                    Text(network)
                    Text("•")
                }
            } else {
                if let langCode = item?.cachedLanguage ?? result?.originalLanguage {
                    let lang = Locale.current.localizedString(forLanguageCode: langCode) ?? langCode.uppercased()
                    Text(lang)
                    Text("•")
                }
            }

            if let genre = item?.cachedGenres.first ?? result?.genres.first {
                Text(genre)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    } else {
        if let year = yearLabel {
            Text(year)
                .font(.system(size: mode == .hero ? 12 : 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
.frame(height: mode == .hero ? nil : 50, alignment: .topLeading)
.padding(.horizontal, 4)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var posterLayer: some View {
        let content = Group {
            if let urlString = posterURL, let url = URL(string: urlString) {
                // Request slightly more pixels (3x) to ensure crispness even on high-end Retina screens
                CachedImage(url: url, targetSize: CGSize(width: width * 3, height: height * 3)) {
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
            let geomID = item?.id ?? "\(metadata?.id.hashValue ?? 0)"
            if !geomID.isEmpty {
                content.matchedGeometryEffect(id: "poster_\(geomID)", in: ns)
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
            withAnimation(.spring()) {
                next.isWatched = true
                item.lastInteractionDate = Date()
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
        .liquidGlassPill(accentColor: .accentColor, isSolid: false)
    }

    @ViewBuilder
    private func infoRow(for item: MediaItem) -> some View {
        infoRowUI(badgeText: item.badgeText, state: item.state, watchProgressLabel: item.watchProgressLabel, progress: item.progress, isUpcomingSection: isUpcomingSection, isUpcoming: item.isUpcoming)
    }

    @ViewBuilder
    private func infoRowMetadata(for m: MediaThumbnailMetadata) -> some View {
        infoRowUI(badgeText: m.badgeText, state: m.state, watchProgressLabel: m.watchProgress, progress: m.progress, isUpcomingSection: isUpcomingSection, isUpcoming: m.isUpcoming)
    }

    @ViewBuilder
    private func infoRowUI(badgeText: String?, state: MediaState?, watchProgressLabel: String?, progress: Double?, isUpcomingSection: Bool, isUpcoming: Bool) -> some View {
        Group {
            let isAvailable = badgeText?.contains("Streaming") == true || badgeText?.contains("Available") == true || (badgeText?.contains("🍿 Season") == true && badgeText?.contains("Drops") == false)

            if state == .completed {
                // NO PILL FOR COMPLETED
                EmptyView()
            } else if (isUpcomingSection || isUpcoming) && badgeText != nil {
                // FORCE BADGE FOR UPCOMING SECTION OR UPCOMING ITEMS IN LIBRARY
                badgeContent(badgeText: badgeText!, isAvailable: isAvailable, state: state, progress: progress)
            } else if (state == .active || state == .rewatching) && watchProgressLabel != nil {
                // HIDE BOTTOM PILL FOR ACTIVE IF NOT UPCOMING (redundant with top-right badge)
                EmptyView()
            } else if let badgeText = badgeText, isUpcomingSection {
                // BADGE ONLY IF UPCOMING SECTION
                badgeContent(badgeText: badgeText, isAvailable: isAvailable, state: state, progress: progress)
            } else if state == .wishlist && isUpcomingSection {
                Text("Watchlist")
                    .foregroundStyle(.orange)
                    .liquidGlassPill(accentColor: .primary, isSolid: false)
            } else if state == .onHold {
                Text("On Hold (\(watchProgressLabel ?? "Paused"))")
                    .foregroundStyle(Color(red: 0.9, green: 0.5, blue: 0.0))  // Amber
                    .liquidGlassPill(accentColor: .primary, isSolid: false)
            } else if state == .dropped {
                Text("Dropped (\(watchProgressLabel ?? "End"))")
                    .foregroundStyle(Color(red: 0.8, green: 0.2, blue: 0.2))  // Red
                    .liquidGlassPill(accentColor: .primary, isSolid: false)
            }
        }
    }

    @ViewBuilder
    private func badgeContent(badgeText: String, isAvailable: Bool, state: MediaState?, progress: Double?) -> some View {
        HStack(spacing: 6) {
            // Funky & Vibey Icon
            Image(systemName: isAvailable ? "play.fill" : "sparkles")
                .font(.system(size: 10, weight: .black))
                .symbolEffect(.pulse, options: .repeating, value: isAvailable)
                .foregroundStyle(isAvailable ? .white : .yellow)

            Text(badgeText)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .font(.system(size: 9, weight: .bold))
        }
        .liquidGlassPill(
            accentColor: isAvailable ? Color.semanticGreen(for: colorScheme) : .primary,
            isSolid: isAvailable,
            progress: (isAvailable && (state == .active || state == .rewatching)) ? progress : nil
        )
    }

    @ViewBuilder
    private func libraryContextMenu(for item: MediaItem) -> some View {
        Section("Status") {
            ForEach(availableStates(for: item), id: \.self) { state in
                Button(state.displayName) {
                    withAnimation {
                        item.state = state
                        item.lastInteractionDate = Date()
                    }
                }
            }
        }
        Divider()
        Button(role: .destructive) {
            NotificationManager.shared.cancelNotification(for: item)
            modelContext.delete(item)
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    private func availableStates(for item: MediaItem) -> [MediaState] {
        guard item.type == .tvShow else { return MediaState.allCases }
        if item.hasWatchedAllEpisodes { return [.completed, .rewatching] }
        if item.hasWatchedAnyEpisode {
            return [.active, .onHold, .dropped, .rewatching, .completed]
        }
        return MediaState.allCases
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
        case "OnHold": return "Nothing on Hold"
        case "Dropped": return "No Dropped Items"
        case "Rewatching": return "Not Re-watching Anything"
        default: return "Library is Empty"
        }
    }

    private var icon: String {
        switch category {
        case "Upcoming": return "calendar.badge.clock"
        case "InProgress": return "play.slash"
        case "Watchlist": return "list.bullet.rectangle"
        case "OnHold": return "pause.circle"
        case "Dropped": return "xmark.bin"
        case "Rewatching": return "arrow.clockwise.circle"
        default: return "tray"
        }
    }

    private var description: String {
        switch category {
        case "Upcoming": return "No releases or new episodes are expected soon."
        case "InProgress": return "You're all caught up! Start something new from your watchlist."
        case "Watchlist": return "Your watchlist is empty. Search for something to add!"
        case "OnHold": return "Items you've paused will appear here."
        case "Dropped": return "Items you've decided not to finish."
        case "Rewatching": return "Everything you decide to experience again will live here."
        default: return "Start building your collection by searching for movies or shows."
        }
    }
}

extension Color {
    static let detailAccent = Color.blue  // Low opacity blue for detailed view tags

    static func semanticGreen(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color.green // Return to vibrant bright green
        } else {
            return Color(red: 0.0, green: 0.6, blue: 0.2)  // More vibrant but high-contrast green for Light Mode
        }
    }

    static func semanticRed(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color.red  // Existing bright red
        } else {
            return Color(red: 0.75, green: 0.1, blue: 0.1)  // Deeper red for light mode
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
        let hues: [Double] = [
            0.0,    // Red
            0.1,    // Orange
            0.15,   // Amber
            0.45,   // Teal
            0.55,   // Blue
            0.65,   // Indigo
            0.75,   // Purple
            0.85    // Pink
        ]
        
        let randomHue = hues.randomElement() ?? 0.5
        // Use very soft, pastel-leaning colors so they don't clash with strong logo branding
        let saturation: Double = colorScheme == .dark ? 0.25 : 0.35
        let brightness: Double = colorScheme == .dark ? 0.95 : 0.8
        
        return Color(hue: randomHue, saturation: saturation, brightness: brightness)
    }
}

struct ThemeBackground: ViewModifier {
    var networkOverride: String? = nil
    var tintOverride: Color? = nil
    var disableBrandBackground: Bool = false
    @AppStorage("theme_style") private var themeStyle: ThemeStyle = .standard
    @AppStorage("app_accent") private var appAccent: AppAccent = .indigo
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        let isAsleep = SleepManager.shared.isAsleep
        
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
                    }
                }
                .ignoresSafeArea()
            }
    }
}

extension View {
    func appBackground(network: String? = nil, tint: Color? = nil, disableBrandBackground: Bool = false) -> some View {
        self.modifier(ThemeBackground(networkOverride: network, tintOverride: tint, disableBrandBackground: disableBrandBackground))
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
