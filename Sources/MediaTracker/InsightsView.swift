import SwiftData
import SwiftUI

private final class StatsCache: @unchecked Sendable {
    static let shared = StatsCache()
    private var stats: LibraryStats?
    private var savedAt: Date?
    private let lock = NSLock()

    func load() -> LibraryStats? {
        lock.lock()
        defer { lock.unlock() }
        guard let savedAt, savedAt > Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? .distantPast else {
            self.stats = nil
            return nil
        }
        return stats
    }

    func save(_ s: LibraryStats) {
        lock.lock()
        defer { lock.unlock() }
        stats = s
        savedAt = Date()
    }
}

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var stats: LibraryStats?
    @State private var isLoading = true

    @State private var recentItems: [MediaItem] = []

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()

            if isLoading {
                InsightsSkeletonView()
            } else if let stats = stats {
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.section) {
                        // Title with Link to Cinephile Lab
                        HStack {
                            Text("Insights")
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                            
                            Spacer()
                            
                            NavigationLink(value: CinephileLabDestination()) {
                                HStack(spacing: 6) {
                                    Image(systemName: "chart.bar.doc.horizontal.fill")
                                    Text("Cinephile Lab")
                                }
                                .font(.system(size: 13, weight: .bold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 24)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)

                        // 1. Hero Stats
                        HeroStatGrid(stats: stats)
                            .padding(.horizontal, AppTheme.Spacing.pageMargin)

                        // 2. Taste Profile
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                            SectionHeader(title: "Taste Profile", icon: "heart.circle.fill", iconColor: .pink)
                            
                            HStack(alignment: .center, spacing: AppTheme.Spacing.large) {
                                RatingDonutChart(
                                    loved: stats.lovedCount,
                                    liked: stats.likedCount,
                                    disliked: stats.dislikedCount,
                                    unrated: max(0, (stats.totalMovies + stats.totalTVShows) - stats.lovedCount - stats.likedCount - stats.dislikedCount)
                                )
                                .frame(maxHeight: .infinity)
                                
                                TastePreferencesCard(stats: stats)
                                    .frame(maxHeight: .infinity)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        }

                        // 3. Cast & Crew
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                            SectionHeader(title: "Cast & Crew", icon: "person.3.fill", iconColor: .teal)
                            TalentLedgerView(stats: stats)
                        }

                        // 4. Recently Watched
                        if !recentItems.isEmpty {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                                SectionHeader(title: "Recently Watched", icon: "play.circle.fill", iconColor: .blue)
                                RecentlyWatched(items: recentItems)
                            }
                        }
                    }
                    .padding(.bottom, AppTheme.Spacing.section)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .navigationDestination(for: CinephileLabDestination.self) { _ in
                    CinephileLabView(stats: stats, barcodeData: stats.barcodeData, recentItems: recentItems)
                }
            }
        }
        .onAppear(perform: refreshData)
    }

    private func refreshData() {
        if let cached = StatsCache.shared.load() {
            let cutoff = Date(timeIntervalSinceNow: -30 * 86400)
            var descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { ($0.lastInteractionDate ?? cutoff) >= cutoff }, sortBy: [SortDescriptor(\.lastInteractionDate, order: .reverse)])
            descriptor.fetchLimit = 50
            let recent = (try? modelContext.fetch(descriptor)) ?? []
            self.stats = cached
            self.recentItems = recent
            self.isLoading = false
            return
        }

        let container = modelContext.container
        Task {
            await performFetch(container: container)
        }
    }

    private func performFetch(container: ModelContainer) async {
        let actor = LibraryStatsActor(modelContainer: container)
        let result = await actor.fetchStats()
        StatsCache.shared.save(result)

        let cutoff = Date(timeIntervalSinceNow: -30 * 86400)
        var descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { ($0.lastInteractionDate ?? cutoff) >= cutoff }, sortBy: [SortDescriptor(\.lastInteractionDate, order: .reverse)])
        descriptor.fetchLimit = 50
        let recent: [MediaItem]
        do {
            let context = ModelContext(container)
            recent = try context.fetch(descriptor)
        } catch {
            recent = []
        }

        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.stats = result
                self.recentItems = recent
                self.isLoading = false
            }
        }
    }

    @MainActor
    private func fetchRecentItems() async -> [MediaItem] {
        let cutoff = Date(timeIntervalSinceNow: -30 * 86400)
        var descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate<MediaItem> { ($0.lastInteractionDate ?? cutoff) >= cutoff }, sortBy: [SortDescriptor(\.lastInteractionDate, order: .reverse)])
        descriptor.fetchLimit = 50
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

// MARK: - Dashboard Card Container

struct DashboardCard<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(AppTheme.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.02))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04), lineWidth: 0.5)
            )
    }
}

// MARK: - Activity Heatmap

struct RecentlyWatched: View {
    let items: [MediaItem]
    @State private var hoveredItemID: String? = nil

    private var recentItems: [MediaItem] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -5, to: Date()) ?? Date()
        return items
            .filter { item in
                guard let date = item.lastInteractionDate else { return false }
                return date >= cutoff && item.stateValue != "Wishlist"
            }
            .sorted { a, b in
                (a.lastInteractionDate ?? .distantPast) > (b.lastInteractionDate ?? .distantPast)
            }
    }

    var body: some View {
        if !recentItems.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        ForEach(recentItems) { item in
                            titleCard(item: item)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    @ViewBuilder
    private func titleCard(item: MediaItem) -> some View {
        let isHovered = hoveredItemID == item.id

        ZStack(alignment: .topTrailing) {
            if let url = item.posterURL, let imageURL = URL(string: url) {
                CachedImage(url: imageURL, targetSize: CGSize(width: 90, height: 135)) {
                    ProgressView().controlSize(.small)
                }
                .scaledToFill()
                .frame(width: 90, height: 135)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
            } else {
                RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 90, height: 135)
                    .overlay(
                        Image(systemName: "film")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                    )
            }

            if item.tasteValue != TasteValue.none.rawValue {
                Text(tasteEmoji(item.tasteValue))
                    .font(.system(size: 11))
                    .padding(4)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .padding(6)
            }
        }
        .frame(width: 90, height: 135)
        .shadow(color: .black.opacity(isHovered ? 0.25 : 0.1), radius: isHovered ? 8 : 4, x: 0, y: isHovered ? 4 : 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.springSnappy) {
                hoveredItemID = hovering ? item.id : nil
            }
        }
    }

    private func tasteEmoji(_ taste: String) -> String {
        guard let tasteVal = TasteValue(rawValue: taste) else { return "" }
        switch tasteVal {
        case .love: return "♥"
        case .like: return "👍"
        case .dislike: return "👎"
        case .none: return ""
        }
    }
}

// MARK: - Hero Stats Grid (Claymorphic Popcorn Bubbles)

struct ClaymorphicCard: View {
    let color: Color
    let isHovered: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            // 3D Puffed background color
            .fill(
                LinearGradient(
                    colors: [
                        color.opacity(colorScheme == .dark ? 0.16 : 0.12),
                        color.opacity(colorScheme == .dark ? 0.05 : 0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            // Outer subtle border
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        isHovered ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(colorScheme == .dark ? 0.25 : 0.15)),
                        lineWidth: isHovered ? 1.5 : 0.7
                    )
            )
            // Inner Highlight (Claymorphic Glossy Highlight)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.45), lineWidth: 3)
                    .blur(radius: 1.5)
                    .offset(x: 1.5, y: 1.5)
                    .mask(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
            )
            // Inner Shadow (Claymorphic Depth)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), lineWidth: 4)
                    .blur(radius: 2)
                    .offset(x: -2, y: -2)
                    .mask(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
            )
    }
}

struct ClaymorphicHeroCard: View {
    let emoji: String
    let value: String
    let label: String
    let detail: LocalizedStringKey
    let color: Color

    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            // Left: Cute Mascot Emoji
            Text(emoji)
                .font(.system(size: 32))
                .scaleEffect(isHovered ? 1.2 : 1.0)
                .rotationEffect(Angle(degrees: isHovered ? -10 : 0))
                .offset(y: isHovered ? -4 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.5), value: isHovered)
                .frame(width: 44, height: 44)

            // Right: Text Details
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(color.opacity(0.8))
                    .lineLimit(1)
                
                Text(value)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(detail)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .frame(width: 240, height: 86, alignment: .leading)
        .background(
            ClaymorphicCard(color: color, isHovered: isHovered)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: color.opacity(isHovered ? 0.15 : 0.0), radius: 10, x: 0, y: 5)
        .shadow(color: .black.opacity(isHovered ? 0.06 : 0.02), radius: isHovered ? 6 : 3, x: 0, y: isHovered ? 3 : 1)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}

struct HeroStatGrid: View {
    let stats: LibraryStats

    var completionRate: Double {
        let total = stats.totalMovies + stats.totalTVShows
        guard total > 0 else { return 0 }
        return Double(stats.completedMovies + stats.completedTVShows) / Double(total)
    }

    var overallAffinity: Double {
        let totalRated = stats.lovedCount + stats.likedCount + stats.dislikedCount
        guard totalRated > 0 else { return 0 }
        let score = (3.0 * Double(stats.lovedCount) + 1.0 * Double(stats.likedCount) - 2.0 * Double(stats.dislikedCount)) / (3.0 * Double(totalRated))
        return max(0, score)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ClaymorphicHeroCard(
                    emoji: "🍿",
                    value: "\(stats.totalMovies + stats.totalTVShows)",
                    label: "Titles",
                    detail: "\(stats.totalMovies) \(Image(systemName: "film")) · \(stats.totalTVShows) \(Image(systemName: "tv"))",
                    color: .pink
                )
                ClaymorphicHeroCard(
                    emoji: "⏱️",
                    value: formatWatchTimeCompact(minutes: stats.totalWatchTimeMinutes),
                    label: "Watch Time",
                    detail: "\(stats.totalEpisodesWatched) eps",
                    color: .orange
                )
                ClaymorphicHeroCard(
                    emoji: "🏆",
                    value: String(format: "%.0f%%", completionRate * 100),
                    label: "Completion",
                    detail: "\(stats.completedMovies + stats.completedTVShows)/\(stats.totalMovies + stats.totalTVShows)",
                    color: .teal
                )
                ClaymorphicHeroCard(
                    emoji: "💖",
                    value: String(format: "%.0f%%", overallAffinity * 100),
                    label: "Affinity",
                    detail: "\(stats.lovedCount)♥ · \(stats.likedCount)👍 · \(stats.dislikedCount)👎",
                    color: .purple
                )
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Rating Donut Chart

struct RatingDonutChart: View {
    let loved: Int
    let liked: Int
    let disliked: Int
    let unrated: Int

    private var total: Int { loved + liked + disliked + unrated }
    private var hasData: Bool { total > 0 }

    private struct ComputedSegment: Identifiable {
        let id: Int
        let start: Double
        let end: Double
        let color: Color
        let label: String
        let value: Int
    }

    private var computedSegments: [ComputedSegment] {
        let raw = [
            (loved, Color.red, "Love"),
            (liked, Color.blue, "Like"),
            (unrated, Color.gray.opacity(0.35), "Unrated"),
            (disliked, Color.orange, "Dislike")
        ]

        var currentSum = 0.0
        var list: [ComputedSegment] = []
        for (index, item) in raw.enumerated() {
            guard item.0 > 0 else { continue }
            let fraction = Double(item.0) / Double(max(1, total))
            list.append(ComputedSegment(
                id: index,
                start: currentSum,
                end: currentSum + fraction,
                color: item.1,
                label: item.2,
                value: item.0
            ))
            currentSum += fraction
        }
        return list
    }

    var body: some View {
        DashboardCard {
            HStack(spacing: AppTheme.Spacing.xLarge) {
                ZStack {
                    if hasData {
                        let arcWidth: CGFloat = 22
                        ForEach(computedSegments) { seg in
                            DonutArc(start: seg.start, end: seg.end, color: seg.color, lineWidth: arcWidth)
                        }
                    } else {
                        Circle()
                            .stroke(Color.primary.opacity(0.06), lineWidth: 22)
                    }

                    VStack(spacing: 2) {
                        Text("\(total)")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("TOTAL\nRATED")
                            .font(AppTheme.Font.mono)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 150, height: 150)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(computedSegments) { seg in
                        HStack(spacing: AppTheme.Spacing.small) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(seg.color)
                                .frame(width: 12, height: 12)

                            Text(seg.label)
                                .font(AppTheme.Font.bodyBold)
                                .foregroundStyle(.primary)
                                .frame(width: 60, alignment: .leading)

                            Text("\(seg.value)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(String(format: "%.0f%%", (seg.end - seg.start) * 100))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct DonutArc: View {
    let start: Double
    let end: Double
    let color: Color
    let lineWidth: CGFloat

    @State private var animatedEnd: Double = 0.0

    var body: some View {
        Circle()
            .trim(from: start, to: animatedEnd)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .onAppear {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                    animatedEnd = end
                }
            }
            .onChange(of: end) { _, newValue in
                animatedEnd = newValue
            }
    }
}


// MARK: - Taste Preferences

struct TastePreferencesCard: View {
    let stats: LibraryStats

    var body: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            PreferenceBlock(
                title: "Top Studio",
                value: stats.topRatedStudios.first?.name ?? "—",
                score: stats.topRatedStudios.first?.score,
                icon: "building.2.fill",
                color: .orange
            )
            PreferenceBlock(
                title: "Top Network",
                value: stats.topRatedNetworks.first?.name ?? "—",
                score: stats.topRatedNetworks.first?.score,
                icon: "antenna.radiowaves.left.and.right",
                color: .teal
            )
            PreferenceBlock(
                title: "Top Language",
                value: stats.topRatedLanguages.first?.name ?? "—",
                score: stats.topRatedLanguages.first?.score,
                icon: "character.bubble.fill",
                color: .purple
            )
        }
    }
}

struct PreferenceBlock: View {
    let title: String
    let value: String
    let score: Double?
    let icon: String
    let color: Color

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            ZStack {
                Circle()
                    .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 16, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.Font.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                Text(value)
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()

            if let score = score, score > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.0f%%", score * 100))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                    Text("Affinity")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(color.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.02))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04), lineWidth: 0.5)
        )
    }
}



// MARK: - Helpers

func formatWatchTimeCompact(minutes: Int) -> String {
    let days = minutes / 1440
    let hours = (minutes % 1440) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    return "\(hours)h \(minutes % 60)m"
}

