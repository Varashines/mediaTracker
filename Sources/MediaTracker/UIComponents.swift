import SwiftUI

struct LiquidGlassModifier: ViewModifier {
    let accentColor: Color
    let isSolid: Bool
    let foregroundColor: Color?
    @Environment(\.colorScheme) var colorScheme

    init(accentColor: Color, isSolid: Bool = false, foregroundColor: Color? = nil) {
        self.accentColor = accentColor
        self.isSolid = isSolid
        self.foregroundColor = foregroundColor
    }

    func body(content: Content) -> some View {
        let isLight = accentColor.isLightColor

        // If solid, always white. If frosted, use primary (adaptive black/white).
        let defaultForeground = isSolid ? Color.white : .primary
        let foreground = foregroundColor ?? defaultForeground

        // If solid, high opacity. If frosted, subtle tint.
        let tintOpacity = isSolid ? (colorScheme == .dark ? 0.8 : 0.9) : (isLight ? 0.35 : 0.5)

        return
            content
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background {
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
            }
            .clipShape(Capsule())
            .overlay {
                // Subtle stroke for definition
                Capsule()
                    .stroke(
                        accentColor.opacity(isSolid ? 1.0 : (isLight ? 0.7 : 0.5)), lineWidth: 0.5)
            }
    }
}

extension View {
    func liquidGlassPill(accentColor: Color, isSolid: Bool = false, foregroundColor: Color? = nil)
        -> some View
    {
        self.modifier(
            LiquidGlassModifier(
                accentColor: accentColor, isSolid: isSolid, foregroundColor: foregroundColor))
    }
}

// MARK: - Status Badge View
struct StatusBadgeView: View {
    let item: MediaItem?
    let result: MediaSearchResult?

    init(item: MediaItem) {
        self.item = item
        self.result = nil
    }

    init(result: MediaSearchResult) {
        self.item = nil
        self.result = result
    }

    var body: some View {
        if let item = item {
            itemStatusBadge(item)
        } else if let result = result {
            resultStatusBadge(result)
        }
    }

    @ViewBuilder
    private func itemStatusBadge(_ item: MediaItem) -> some View {
        Group {
            if item.isUpcoming {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                    .liquidGlassPill(accentColor: .primary, isSolid: false)
            } else if item.state == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)
                    .liquidGlassPill(accentColor: .green, isSolid: true)
            } else if item.isActive || item.state == .rewatching {
                HStack(spacing: 2) {
                    Image(
                        systemName: item.state == .rewatching
                            ? "arrow.clockwise" : "play.circle.fill")
                    if item.state != .rewatching {
                        Text(item.watchProgressLabel ?? "")
                    }
                }
                .foregroundStyle(.white)
                .liquidGlassPill(
                    accentColor: item.state == .rewatching ? .orange : .indigo, isSolid: true)
            } else if item.state == .onHold {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.white)
                    .liquidGlassPill(
                        accentColor: Color(red: 0.9, green: 0.5, blue: 0.0), isSolid: true)  // Amber
            } else if item.state == .dropped {
                Image(systemName: "xmark.bin.fill")
                    .foregroundStyle(.white)
                    .liquidGlassPill(
                        accentColor: Color(red: 0.8, green: 0.2, blue: 0.2), isSolid: true)  // Muted Red
            } else if item.state == .wishlist && !item.isUpcoming {
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
    let result: MediaSearchResult?
    let mode: DisplayMode
    var showTypeBadge: Bool = true
    var isLocalInSearch: Bool = false
    var action: (() -> Void)? = nil
    var namespace: Namespace.ID? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("app_accent") private var appAccent: AppAccent = .indigo
    @State private var isHovered = false
    @State private var isButtonHovered = false

    init(
        item: MediaItem, mode: DisplayMode = .grid, showTypeBadge: Bool = true,
        namespace: Namespace.ID? = nil, action: (() -> Void)? = nil
    ) {
        self.item = item
        self.result = nil
        self.mode = mode
        self.showTypeBadge = showTypeBadge
        self.namespace = namespace
        self.action = action
    }

    init(result: MediaSearchResult, isLocal: Bool = false, action: @escaping () -> Void) {
        self.item = nil
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
        item?.title ?? result?.title ?? ""
    }

    private var posterURL: String? {
        item?.posterURL ?? result?.posterURL
    }

    private var type: MediaType {
        item?.type ?? result?.type ?? .movie
    }

    private var yearLabel: String? {
        if let date = item?.releaseDate {
            return Calendar.current.dateComponents([.year], from: date).year.map { String($0) }
        } else if let dateString = result?.releaseDate, dateString.count >= 4 {
            return String(dateString.prefix(4))
        }
        return nil
    }

    private var isAdded: Bool {
        item != nil || isLocalInSearch
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

                // 3. Top Pills
                topPills

                // 5. Info Pill (Bottom Center)
                if let item = item, item.isUpcoming || mode == .hero {
                    VStack {
                        Spacer()
                        infoRow(for: item)
                            .padding(6)
                    }
                }
            }
            .frame(width: width, height: height)
            .background {
                if let item = item, let ns = namespace {
                    Color.clear.matchedGeometryEffect(id: "poster_bg_\(item.id)", in: ns)
                }
            }
            .cornerRadius(mode == .hero ? 16 : 12)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.2), value: isHovered)
// 6. Info Section (Below)
VStack(alignment: .leading, spacing: 1) {
    Text(title)
        .font(.system(size: mode == .hero ? 15 : 13, weight: .bold))
        .foregroundStyle(.primary)
        .lineLimit(2)
        .multilineTextAlignment(.leading)

    if mode == .search {
        HStack(spacing: 4) {
            if let year = yearLabel {
                Text(year)
            }

            Text("•")

            if type == .tvShow {
                if let network = item?.cachedNetwork {
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
                CachedImage(url: url, targetSize: CGSize(width: width * 2, height: height * 2)) {
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

        if let item = item, let ns = namespace {
            content.matchedGeometryEffect(id: "poster_\(item.id)", in: ns)
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
    private var topPills: some View {
        HStack(alignment: .top) {
            if showTypeBadge {
                typeBadge
            }
            Spacer()

            if let item = item {
                StatusBadgeView(item: item)
            }
        }
        .padding(6)
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
        Group {
            if item.isUpcoming {
                Text(item.nextAiringLabel ?? "")
                    .liquidGlassPill(
                        accentColor: item.isRecentlyReleased
                            ? Color.semanticGreen(for: colorScheme) : .primary,
                        isSolid: item.isRecentlyReleased
                    )
            } else if item.state == .wishlist {
                Text("Watchlist")
                    .foregroundStyle(.orange)
                    .liquidGlassPill(accentColor: .primary, isSolid: false)
            } else if item.state == .completed {
                Text("Completed")
                    .foregroundStyle(.primary)
                    .liquidGlassPill(accentColor: .primary, isSolid: false)
            } else if item.state == .onHold {
                Text("On Hold (\(item.watchProgressLabel ?? "Paused"))")
                    .foregroundStyle(Color(red: 0.9, green: 0.5, blue: 0.0))  // Amber
                    .liquidGlassPill(accentColor: .primary, isSolid: false)
            } else if item.state == .dropped {
                Text("Dropped (\(item.watchProgressLabel ?? "End"))")
                    .foregroundStyle(Color(red: 0.8, green: 0.2, blue: 0.2))  // Red
                    .liquidGlassPill(accentColor: .primary, isSolid: false)
            } else if item.state == .rewatching {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Re-watching")
                }
                .foregroundStyle(.orange)
                .liquidGlassPill(accentColor: .primary, isSolid: false)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                    Text(item.watchProgressLabel ?? "In Progress")
                }
                .liquidGlassPill(accentColor: appAccent.color, isSolid: true)
            }
        }
        .font(.system(size: 9, weight: .bold))
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
            SpotlightManager.shared.removeItem(item)
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
            return Color.green  // Existing bright green for OLED/Dark
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
        content
            .background {
                ZStack {
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
