import SwiftUI
import SwiftData

struct ContinueWatchingCarousel: View {
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let onSelect: (MediaItem) -> Void
    var onDiscoverySpotlight: (() -> Void)?
    
    @Query private var activeItems: [MediaItem]
    
    init(namespace: Namespace.ID, isFastScrolling: Bool, onSelect: @escaping (MediaItem) -> Void, onDiscoverySpotlight: (() -> Void)? = nil) {
        self.namespace = namespace
        self.isFastScrolling = isFastScrolling
        self.onSelect = onSelect
        self.onDiscoverySpotlight = onDiscoverySpotlight
        
        let predicate = #Predicate<MediaItem> { item in
            (item.stateValue == "Active" || item.stateValue == "Wishlist") && item.tasteValue != "Dislike"
        }
        
        // Optimization: limit the fetch to 40 items to ensure smooth loading while still having enough for filtering
        // We use 40 instead of 20 because the displayItems property performs additional manual filtering.
        var descriptor = FetchDescriptor<MediaItem>(predicate: predicate, sortBy: [SortDescriptor(\.lastInteractionDate, order: .reverse)])
        descriptor.fetchLimit = 40
        self._activeItems = Query(descriptor)
    }
    
    @State private var scrollProgress: Double = 0
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    private let scrollSpace = "CW_Scroll"
    
    private var displayItems: [MediaItem] {
        let now = Date()
        let filtered = activeItems.filter { item in
            if item.releaseDate == nil && item.cachedNextAiringDate == nil { return false }
            let isActive = item.stateValue == "Active"
            let isWishlist = item.stateValue == "Wishlist"
            let date = item.cachedNextAiringDate ?? item.releaseDate ?? .distantPast
            let isFuture = date > now
            let badge = item.storedSmartBadgeLabel
            let isRecent = badge == "NEW" || badge == "BINGE DROP"
            return ((isActive || isWishlist) && !isFuture) || isRecent
        }.sorted { (itemA: MediaItem, itemB: MediaItem) -> Bool in
            let isAStreaming = itemA.storedSmartBadgeLabel == "NEW"
            let isBStreaming = itemB.storedSmartBadgeLabel == "NEW"
            if isAStreaming != isBStreaming { return isAStreaming }
            let isABinge = itemA.storedSmartBadgeLabel == "BINGE DROP"
            let isBBinge = itemB.storedSmartBadgeLabel == "BINGE DROP"
            if isABinge != isBBinge { return isABinge }
            return (itemA.lastInteractionDate ?? .distantPast) > (itemB.lastInteractionDate ?? .distantPast)
        }
        return Array(filtered.prefix(20))
    }

    var body: some View {
        let items = displayItems
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Continue Watching", 
                icon: "play.fill", 
                iconColor: .blue,
                scrollProgress: items.count > 1 ? scrollProgress : nil
            )
            
            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        Spacer(minLength: 10)
                        ForEach(items) { item in
                            Button { onSelect(item) } label: {
                                MediaThumbnailView(item: item, mode: .hero, namespace: namespace, isFastScrolling: isFastScrolling)
                            }
                            .buttonStyle(.interactive)
                        }
                        Spacer(minLength: 10)
                    }
                    .padding(.vertical, 15)
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
                .scrollBounceBehavior(.basedOnSize)
                .coordinateSpace(name: scrollSpace)
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
                    scrollProgress = min(1.0, currentScroll / maxScroll)
                }
                .scrollClipDisabled()
            } else {
                // Discovery Spotlight Empty State
                Button {
                    onDiscoverySpotlight?()
                } label: {
                    HStack(spacing: 24) {
                        Image(systemName: "sparkles.tv.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                            .frame(width: 80, height: 80)
                            .background(Color.accentColor.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ready to start watching?")
                                .font(.headline.bold())
                                .foregroundStyle(.primary)
                            Text("Explore the Discovery Hub to find your next favorite show.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 30)
                .padding(.vertical, 15)
            }
        }
    }
}
