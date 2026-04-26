import SwiftUI
import SwiftData

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
                intelligentBadge(label: label, icon: icon, isSparkle: metadata.isSparkleBadge, remaining: metadata.remainingCount)
            } else if metadata.type == .movie {
                statusUI(
                    isUpcoming: metadata.isUpcoming,
                    state: metadata.state,
                    badgeText: metadata.badgeText,
                    watchProgressLabel: metadata.watchProgress,
                    nextEpisodeLabel: metadata.nextEpisodeToWatchLabel,
                    progress: metadata.progress
                )
            }
        } else if let item = item, item.modelContext != nil, !item.isDeleted {
            if let label = item.storedSmartBadgeLabel, let icon = item.storedSmartBadgeIcon {
                intelligentBadge(label: label, icon: icon, isSparkle: item.storedSmartBadgeIsSparkle, remaining: item.remainingEpisodesCount)
            } else if item.type == .movie {
                statusUI(
                    isUpcoming: item.storedIsUpcoming,
                    state: item.state,
                    badgeText: item.gridBadgeText,
                    watchProgressLabel: item.storedWatchProgressLabel,
                    nextEpisodeLabel: item.storedNextEpisodeLabel,
                    progress: item.storedProgress
                )
            }
        } else if let res = result, res.type == .movie {
             statusUI(isUpcoming: false, state: .wishlist, badgeText: nil, watchProgressLabel: nil, nextEpisodeLabel: nil, progress: nil)
        }
    }

    @ViewBuilder
    private func intelligentBadge(label: String, icon: String, isSparkle: Bool, remaining: Int? = nil) -> some View {
        let isBinge = label == "BINGE"
        
        HStack(spacing: 4) {
            Image(systemName: icon)
            
            if isBinge, let remaining = remaining, remaining > 0 {
                HStack(spacing: 4) {
                    Text("BINGE")
                    Text("•")
                        .opacity(0.5)
                    Text("\(remaining) LEFT")
                        .font(.system(size: 8, weight: .heavy))
                }
            } else {
                Text(label)
            }
        }
        .font(.system(size: 9, weight: .black))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isBinge ? appAccent.color.gradient : (isSparkle ? appAccent.color.gradient : Color.secondary.opacity(0.8).gradient))
        .foregroundStyle(.white)
        .clipShape(Capsule())
        .shadow(color: isBinge ? appAccent.color.opacity(0.4) : .black.opacity(0.1), radius: isBinge ? 6 : 3, y: 2)
        .overlay {
            if isBinge {
                Capsule()
                    .stroke(.white.opacity(0.3), lineWidth: 1)
            }
        }
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
            let displayLabel = nextEpisodeLabel ?? watchProgressLabel ?? currentState.displayName

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

// MARK: - Taste Controls
struct TasteToggle: View {
    @Bindable var item: MediaItem
    let themeColor: Color
    
    var body: some View {
        if item.modelContext != nil && !item.isDeleted {
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
    }
    
    private func setTaste(_ val: String) {
        guard item.modelContext != nil && !item.isDeleted else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if item.tasteValue == val {
                item.tasteValue = "None"
                FeedbackManager.shared.trigger(.click)
            } else {
                item.tasteValue = val
                
                // Creative Feedback Personality
                switch val {
                case "Love": FeedbackManager.shared.trigger(.tasteLove)
                case "Like": FeedbackManager.shared.trigger(.tasteLike)
                case "Dislike": FeedbackManager.shared.trigger(.tasteDislike)
                default: FeedbackManager.shared.trigger(.click)
                }
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
        .buttonStyle(.interactive(feedback: nil))
    }
}

// MARK: - Premium Transitions

struct PerspectiveDepthModifier: ViewModifier {
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .blur(radius: isActive ? 0 : 15)
            .scaleEffect(isActive ? 1.0 : 0.92)
            .offset(y: isActive ? 0 : 20)
            .allowsHitTesting(isActive)
            .zIndex(isActive ? 1 : 0)
    }
}

struct EntranceStaggerModifier: ViewModifier {
    let index: Int
    @State private var isAppeared = false
    
    func body(content: Content) -> some View {
        content
            .offset(y: isAppeared ? 0 : 20)
            .opacity(isAppeared ? 1 : 0)
            .onAppear {
                let delay = Double(index % 24) * 0.03
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(delay)) {
                    isAppeared = true
                }
            }
    }
}

extension View {
    func entranceStagger(index: Int) -> some View {
        modifier(EntranceStaggerModifier(index: index))
    }
}

// MARK: - Skeleton Placeholders

// MARK: - Library Empty State View
struct LibraryEmptyStateView: View {
    let category: String?
    var onExplore: (() -> Void)? = nil

    var body: some View {
        VStack {
            ContentUnavailableView {
                Label(title, systemImage: icon)
            } description: {
                Text(description)
            } actions: {
                if let onExplore = onExplore {
                    Button(action: onExplore) {
                        Text("Explore Discovery Hub")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.interactive)
                }
            }
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
    @State private var phase: Double = 0.6
    
    func body(content: Content) -> some View {
        content
            .opacity(phase)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    phase = 0.3
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
                        
                        // Optimized Static Ambience (Replaces energy-heavy Metal shader)
                        ZStack {
                            RadialGradient(colors: [Color.pink.opacity(isDiscover ? 0.08 : 0.04), .clear], center: .topTrailing, startRadius: 0, endRadius: 800)
                            RadialGradient(colors: [Color.teal.opacity(isDiscover ? 0.08 : 0.04), .clear], center: .bottomLeading, startRadius: 0, endRadius: 800)
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
    @State private var isHovered = false
    @State private var currentScrollX: CGFloat = 0
    @State private var currentIndex: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: title,
                icon: icon,
                iconColor: iconColor,
                scrollProgress: recommendations.count > 1 ? scrollProgress : nil
            )
            .padding(.bottom, 8)
            
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 24) {
                        Spacer(minLength: 16).id("HERO_START") // 16 + 24 spacing = 40px margin
                        
                        ForEach(Array(recommendations.enumerated()), id: \.offset) { index, metadata in
                            if let item = modelContext.model(for: metadata.id) as? MediaItem, !item.isDeleted {
                                NavigationLink(value: item) {
                                    HomeHeroCard(metadata: metadata, item: item, namespace: namespace, isFastScrolling: isFastScrolling)
                                }
                                .buttonStyle(.interactive)
                                .id(index)
                            }
                        }
                        
                        Spacer(minLength: 16)
                    }
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
                .scrollClipDisabled()
                .overlay(alignment: .center) {
                    // Side Arrows
                    HStack {
                        carouselArrow(systemImage: "chevron.left", isLeft: true, proxy: proxy)
                            .opacity((isHovered && currentScrollX < -1) ? 1 : 0)
                        
                        Spacer()
                        
                        carouselArrow(systemImage: "chevron.right", isLeft: false, proxy: proxy)
                            .opacity((isHovered && abs(currentScrollX) < contentWidth - containerWidth - 1) ? 1 : 0)
                    }
                    .padding(.horizontal, 15)
                    .allowsHitTesting(isHovered)
                }
            }
            .frame(height: 320)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { containerWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, newValue in containerWidth = newValue }
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { dict in
                guard let minX = dict[scrollSpace] else { return }
                currentScrollX = minX
                
                // Update currentIndex for arrow navigation
                let cardWidth: CGFloat = 500
                let spacing: CGFloat = 24
                currentIndex = Int(round(abs(minX) / (cardWidth + spacing)))
                
                let maxScroll = max(1, contentWidth - containerWidth)
                let currentScroll = max(0, -minX)
                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                    scrollProgress = min(1.0, currentScroll / maxScroll)
                }
            }
        }
        .onHover { isHovered = $0 }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func carouselArrow(systemImage: String, isLeft: Bool, proxy: ScrollViewProxy) -> some View {
        Button {
            let cardWidth: CGFloat = 500
            let spacing: CGFloat = 24
            let step = max(1, Int(containerWidth / (cardWidth + spacing)))
            let targetIndex = isLeft ? max(0, currentIndex - step) : min(recommendations.count - 1, currentIndex + step)
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                if isLeft && targetIndex == 0 {
                    proxy.scrollTo("HERO_START", anchor: .leading)
                } else {
                    proxy.scrollTo(targetIndex, anchor: .leading)
                }
                currentIndex = targetIndex
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(radius: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Standardized Components

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
    @State private var isHovered = false
    @State private var currentScrollX: CGFloat = 0
    @State private var currentIndex: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: title,
                icon: icon,
                iconColor: iconColor,
                scrollProgress: items.count > 1 ? scrollProgress : nil
            )
            .padding(.bottom, 4)
            
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        Spacer(minLength: 10).id("SHELF_START") // 10 + 20 spacing = 30px margin
                        
                        ForEach(Array(items.enumerated()), id: \.offset) { index, metadata in
                            if let item = modelContext.model(for: metadata.id) as? MediaItem, !item.isDeleted {
                                NavigationLink(value: item) {
                                    MediaThumbnailView(metadata: metadata, mode: .grid, namespace: namespace, isFastScrolling: isFastScrolling)
                                }
                                .buttonStyle(.interactive)
                                .id(index)
                            }
                        }
                        
                        Spacer(minLength: 10)
                    }
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
                .scrollClipDisabled()
                .overlay(alignment: .center) {
                    // Side Arrows
                    HStack {
                        carouselArrow(systemImage: "chevron.left", isLeft: true, proxy: proxy)
                            .opacity((isHovered && currentScrollX < -1) ? 1 : 0)
                        
                        Spacer()
                        
                        carouselArrow(systemImage: "chevron.right", isLeft: false, proxy: proxy)
                            .opacity((isHovered && abs(currentScrollX) < contentWidth - containerWidth - 1) ? 1 : 0)
                    }
                    .padding(.horizontal, 15)
                    .allowsHitTesting(isHovered)
                }
            }
            .frame(height: 270)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { containerWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, newValue in containerWidth = newValue }
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { dict in
                guard let minX = dict[scrollSpace] else { return }
                currentScrollX = minX
                
                // Update currentIndex for arrow navigation
                let itemWidth: CGFloat = 160
                let spacing: CGFloat = 20
                currentIndex = Int(round(abs(minX) / (itemWidth + spacing)))

                let maxScroll = max(1, contentWidth - containerWidth)
                let currentScroll = max(0, -minX)
                withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                    scrollProgress = min(1.0, currentScroll / maxScroll)
                }
            }
        }
        .onHover { isHovered = $0 }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func carouselArrow(systemImage: String, isLeft: Bool, proxy: ScrollViewProxy) -> some View {
        Button {
            let itemWidth: CGFloat = 160
            let spacing: CGFloat = 20
            let step = max(1, Int(containerWidth / (itemWidth + spacing)))
            let targetIndex = isLeft ? max(0, currentIndex - step) : min(items.count - 1, currentIndex + step)
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                if isLeft && targetIndex == 0 {
                    proxy.scrollTo("SHELF_START", anchor: .leading)
                } else {
                    proxy.scrollTo(targetIndex, anchor: .leading)
                }
                currentIndex = targetIndex
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(radius: 4)
        }
        .buttonStyle(.plain)
    }
}
