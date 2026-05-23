import SwiftData
import SwiftUI

enum InsightTab: String, CaseIterable, Hashable, Identifiable {
    case profile = "Profile"
    case history = "History"
    var id: String { rawValue }
}

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Namespace private var tabNamespace

    @State private var stats: LibraryStats?
    @State private var isLoading = true
    @State private var selectedTab: InsightTab = .profile

    @Query(sort: \MediaItem.lastInteractionDate, order: .reverse) private var allItems: [MediaItem]

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()

            if isLoading {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 560)
            } else if let stats = stats {
                ScrollView {
                    VStack(spacing: 0) {
                        CapsuleTabBar(
                            selection: $selectedTab,
                            tabs: InsightTab.allCases,
                            icons: [.profile: "person.circle.fill", .history: "clock.arrow.circlepath"],
                            namespace: tabNamespace,
                            label: { $0.rawValue }
                        )
                        .padding(.top, 16)
                        .padding(.bottom, 28)

                        if selectedTab == .profile {
                            profileSection(stats: stats)
                        } else {
                            historySection(stats: stats)
                        }

                        if selectedTab == .history && !allItems.isEmpty {
                            VStack(spacing: AppTheme.Spacing.large) {
                                SectionHeader(title: "Recently Watched", icon: "play.circle.fill", iconColor: .blue)
                                RecentlyWatched(items: allItems)
                            }
                            .padding(.top, AppTheme.Spacing.section)
                        }
                    }
                    .padding(.bottom, 120)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .onAppear(perform: refreshData)
    }

    @ViewBuilder
    private func profileSection(stats: LibraryStats) -> some View {
        VStack(spacing: AppTheme.Spacing.section) {
            SectionHeader(title: "Profile DNA", icon: "person.circle.fill", iconColor: .accentColor)

            VStack(spacing: AppTheme.Spacing.large) {
                CinephileBarcodeView(items: allItems)

                HeroStatGrid(stats: stats)

                HStack(alignment: .top, spacing: AppTheme.Spacing.large) {
                    RatingDonutChart(
                        loved: stats.lovedCount,
                        liked: stats.likedCount,
                        disliked: stats.dislikedCount,
                        unrated: max(0, (stats.totalMovies + stats.totalTVShows) - stats.lovedCount - stats.likedCount - stats.dislikedCount)
                    )

                    TastePreferencesCard(stats: stats)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.xLarge + AppTheme.Spacing.tiny)

            SectionHeader(title: "Genomes", icon: "circle.dotted.circle", iconColor: .indigo)

            GenreGenomeView(items: Array(stats.genreDNA.prefix(8)))

            SectionHeader(title: "Brand Affinity", icon: "square.grid.2x2.fill", iconColor: .teal)

            VStack(spacing: AppTheme.Spacing.large) {
                BrandsLedgerView(stats: stats)
            }
            .padding(.horizontal, AppTheme.Spacing.xLarge + AppTheme.Spacing.tiny)
        }
    }

    @ViewBuilder
    private func historySection(stats: LibraryStats) -> some View {
        VStack(spacing: AppTheme.Spacing.section) {
            SectionHeader(title: "History Timeline", icon: "clock.arrow.circlepath", iconColor: .accentColor)

            VStack(spacing: AppTheme.Spacing.large) {
                DecadeTimeline(decades: stats.decadeDistribution)

                WeeklyWatchArc(points: stats.watchTimeHistory, items: allItems)
            }
            .padding(.horizontal, AppTheme.Spacing.xLarge + AppTheme.Spacing.tiny)

            SectionHeader(title: "Talent Ledger", icon: "person.3.fill", iconColor: .teal)

            VStack(spacing: AppTheme.Spacing.large) {
                TalentLedgerView(stats: stats)
            }
            .padding(.horizontal, AppTheme.Spacing.xLarge + AppTheme.Spacing.tiny)
        }
    }

    private func refreshData() {
        Task {
            let actor = LibraryStatsActor(modelContainer: modelContext.container)
            let result = await actor.fetchStats()
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.stats = result
                    self.isLoading = false
                }
            }
        }
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
                    .padding(.horizontal, AppTheme.Spacing.xLarge + AppTheme.Spacing.tiny)
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

            if item.tasteValue != "None" {
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
        .scaleEffect(isHovered ? 1.06 : 1.0)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.springSnappy) {
                hoveredItemID = hovering ? item.id : nil
            }
        }
    }

    private func tasteEmoji(_ taste: String) -> String {
        switch taste {
        case "Love": return "♥"
        case "Like": return "👍"
        case "Dislike": return "👎"
        default: return ""
        }
    }
}

// MARK: - Hero Stats Grid

struct HeroStatGrid: View {
    let stats: LibraryStats

    var completionRate: Double {
        let total = stats.totalMovies + stats.totalTVShows
        guard total > 0 else { return 0 }
        return Double(stats.completedMovies + stats.completedTVShows) / Double(total)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.large) {
                HeroStatCard(
                    icon: "film.stack.fill",
                    value: "\(stats.totalMovies + stats.totalTVShows)",
                    label: "Titles",
                    detail: "\(stats.totalMovies)m · \(stats.totalTVShows)s"
                )
                HeroStatCard(
                    icon: "clock.fill",
                    value: formatWatchTimeCompact(minutes: stats.totalWatchTimeMinutes),
                    label: "Watch Time",
                    detail: "\(stats.totalEpisodesWatched) eps"
                )
                HeroStatCard(
                    icon: "checkmark.circle.fill",
                    value: String(format: "%.0f%%", completionRate * 100),
                    label: "Completion",
                    detail: "\(stats.completedMovies + stats.completedTVShows)/\(stats.totalMovies + stats.totalTVShows)"
                )
                HeroStatCard(
                    icon: "sparkle",
                    value: "\(stats.genreDNA.count)",
                    label: "Genres",
                    detail: "Explored"
                )
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16) // wider padding to prevent shadow/scale clipping
        }
    }
}

struct HeroStatCard: View {
    let icon: String
    let value: String
    let label: String
    let detail: String

    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.15 : 0.09))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(label)
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !detail.isEmpty {
                    Text(detail)
                        .font(AppTheme.Font.small)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.02))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), lineWidth: 0.5)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0.03), radius: isHovered ? 8 : 4, x: 0, y: isHovered ? 4 : 2)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.springSnappy) {
                isHovered = hovering
            }
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
                        let arcWidth: CGFloat = 20
                        ForEach(computedSegments) { seg in
                            DonutArc(start: seg.start, end: seg.end, color: seg.color, lineWidth: arcWidth)
                        }
                    } else {
                        Circle()
                            .stroke(Color.primary.opacity(0.06), lineWidth: 20)
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
                .frame(width: 130, height: 130)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
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

// MARK: - Genre DNA (Pills)

struct GenreGenomeView: View {
    let items: [(name: String, percentage: Double)]

    var body: some View {
        if items.isEmpty {
            HStack {
                Spacer()
                Text("No genre data")
                    .font(AppTheme.Font.body)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(height: 50)
            .padding(.horizontal, AppTheme.Spacing.xLarge + AppTheme.Spacing.tiny)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.tiny) {
                    ForEach(Array(items.prefix(8).enumerated()), id: \.element.name) { idx, item in
                        GenreAffinityPill(name: item.name, percentage: item.percentage, index: idx)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.xLarge + AppTheme.Spacing.tiny)
                .padding(.vertical, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

struct GenreAffinityPill: View {
    let name: String
    let percentage: Double
    let index: Int

    private var palette: [Color] {
        [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .mint]
    }

    var body: some View {
        let color = palette[index % palette.count]
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(name)
                .font(AppTheme.Font.bodyBold)
                .foregroundStyle(.primary)

            Text(String(format: "%.0f%%", percentage * 100))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(0.15), lineWidth: 0.5)
        )
    }
}

// MARK: - Decade Distribution

struct DecadeTimeline: View {
    let decades: [DecadeDistributionPoint]

    var body: some View {
        if decades.isEmpty {
            DashboardCard {
                HStack {
                    Spacer()
                    Text("No release date data")
                        .font(AppTheme.Font.body)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(height: 80)
            }
        } else {
            let maxCount = decades.map(\.count).max() ?? 1
            let totalCount = decades.map(\.count).reduce(0, +)
            
            DashboardCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Text("RELEASE ERA DISTRIBUTION")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                        .kerning(1.2)
                        .padding(.bottom, AppTheme.Spacing.micro)
                    
                    VStack(spacing: AppTheme.Spacing.small) {
                        ForEach(decades.sorted(by: { $0.decade > $1.decade })) { item in
                            DecadeDistributionRow(
                                decade: item.decade,
                                count: item.count,
                                percentage: Double(item.count) / Double(max(1, totalCount)),
                                relativeRatio: Double(item.count) / Double(max(1, maxCount))
                            )
                        }
                    }
                }
            }
        }
    }
}

struct DecadeDistributionRow: View {
    let decade: String
    let count: Int
    let percentage: Double
    let relativeRatio: Double

    var body: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            Text(decade)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 50, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.04))
                        .frame(height: 8)

                    Capsule()
                        .fill(Color.accentColor.gradient)
                        .frame(width: geo.size.width * relativeRatio, height: 8)
                }
            }
            .frame(height: 8)

            HStack(spacing: 4) {
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                Text(String(format: "(%.0f%%)", percentage * 100))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 80, alignment: .trailing)
        }
    }
}

// MARK: - Weekly Watch Arc

struct WeeklyWatchArc: View {
    let points: [WatchTimePoint]
    let items: [MediaItem]

    struct DayEntry: Identifiable {
        let id = UUID()
        let date: Date
        let dayName: String
        let dateNum: Int
        let minutes: Int
        let dayItems: [MediaItem]
    }

    private var dayEntries: [DayEntry] {
        let calendar = Calendar.current
        let now = Date()
        var dayMap: [Date: Int] = [:]
        for p in points {
            let start = calendar.startOfDay(for: p.date)
            dayMap[start, default: 0] += p.minutes
        }

        let dayNames = calendar.shortWeekdaySymbols
        var entries: [DayEntry] = []
        for offset in (0..<7).reversed() {
            if let dayDate = calendar.date(byAdding: .day, value: -offset, to: now) {
                let start = calendar.startOfDay(for: dayDate)
                let weekday = calendar.component(.weekday, from: dayDate)
                let dayNum = calendar.component(.day, from: dayDate)
                let mins = dayMap[start, default: 0]

                let dayItems = items.filter { item in
                    guard let interactionDate = item.lastInteractionDate else { return false }
                    return calendar.isDate(interactionDate, inSameDayAs: start) && item.stateValue != "Wishlist"
                }

                entries.append(DayEntry(
                    date: start,
                    dayName: dayNames[weekday - 1].uppercased().prefix(3).description,
                    dateNum: dayNum,
                    minutes: mins,
                    dayItems: Array(dayItems.prefix(4))
                ))
            }
        }
        return entries
    }

    var body: some View {
        let totalMin = dayEntries.map(\.minutes).reduce(0, +)
        let activeDays = dayEntries.filter { $0.minutes > 0 }.count

        DashboardCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                HStack(spacing: AppTheme.Spacing.tiny) {
                    ForEach(dayEntries) { day in
                        DayCard(entry: day)
                            .frame(maxWidth: .infinity)
                    }
                }

                HStack {
                    Text("Total: \(formatWatchTimeCompact(minutes: totalMin))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(activeDays)/7 days active")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct DayCard: View {
    let entry: WeeklyWatchArc.DayEntry

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let isToday = Calendar.current.isDateInToday(entry.date)

        VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
            HStack(spacing: 2) {
                Text(entry.dayName)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(isToday ? Color.accentColor : .secondary)
                Text("\(entry.dateNum)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
            }

            if entry.minutes > 0 {
                Text(formatWatchTimeMini(minutes: entry.minutes))
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.accentColor)

                if !entry.dayItems.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(entry.dayItems.prefix(4)) { item in
                            if let url = item.posterURL, let imageURL = URL(string: url) {
                                CachedImage(url: imageURL, targetSize: CGSize(width: 24, height: 36)) {
                                    Color.clear
                                }
                                .scaledToFill()
                                .frame(width: 24, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                    }
                    .frame(height: 36)
                }
            } else {
                Text("—")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.03))
                    .frame(width: 24, height: 36)
                    .overlay(
                        Image(systemName: "film")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary.opacity(0.5))
                    )
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isToday
                ? Color.accentColor.opacity(colorScheme == .dark ? 0.08 : 0.05)
                : Color.primary.opacity(colorScheme == .dark ? 0.02 : 0.01)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                .stroke(
                    isToday ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.04),
                    lineWidth: isToday ? 1.0 : 0.5
                )
        )
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

// MARK: - Brand Affinity Grid

struct BrandsLedgerView: View {
    let stats: LibraryStats

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.large) {
            // Studios Column
            VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
                Text("TOP RATED STUDIOS")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                    .padding(.leading, AppTheme.Spacing.micro)

                if stats.topRatedStudios.isEmpty {
                    DashboardCard {
                        HStack {
                            Spacer()
                            Text("No studio statistics")
                                .font(AppTheme.Font.body)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(height: 120)
                    }
                } else {
                    DashboardCard {
                        VStack(spacing: 0) {
                            ForEach(Array(stats.topRatedStudios.prefix(5).enumerated()), id: \.element.name) { index, item in
                                BrandRowItem(name: item.name, rank: index + 1, score: item.score, color: .orange)
                                if index < min(stats.topRatedStudios.count, 5) - 1 {
                                    Divider()
                                        .padding(.leading, 32)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Networks Column
            VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
                Text("TOP RATED NETWORKS")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                    .padding(.leading, AppTheme.Spacing.micro)

                if stats.topRatedNetworks.isEmpty {
                    DashboardCard {
                        HStack {
                            Spacer()
                            Text("No network statistics")
                                .font(AppTheme.Font.body)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(height: 120)
                    }
                } else {
                    DashboardCard {
                        VStack(spacing: 0) {
                            ForEach(Array(stats.topRatedNetworks.prefix(5).enumerated()), id: \.element.name) { index, item in
                                BrandRowItem(name: item.name, rank: index + 1, score: item.score, color: .teal)
                                if index < min(stats.topRatedNetworks.count, 5) - 1 {
                                    Divider()
                                        .padding(.leading, 32)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct BrandRowItem: View {
    let name: String
    let rank: Int
    let score: Double
    let color: Color

    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Text("\(rank)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(color.opacity(0.8))
                .frame(width: 16, alignment: .leading)

            Text(name)
                .font(AppTheme.Font.bodyBold)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Text(String(format: "%.0f%%", score * 100))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Helpers

private func formatWatchTimeCompact(minutes: Int) -> String {
    let days = minutes / 1440
    let hours = (minutes % 1440) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    return "\(hours)h \(minutes % 60)m"
}

private func formatWatchTimeMini(minutes: Int) -> String {
    let hours = minutes / 60
    if hours > 0 { return "\(hours)h" }
    return "\(minutes)m"
}

