import SwiftUI
import SwiftData

struct CinephileLabDestination: Hashable {}

struct CinephileLabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var stats: LibraryStats?
    @State private var recentItems: [MediaItem] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                CinephileLabSkeletonView()
            } else if let stats = stats {
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.section) {
                        // Cinephile Spectrum (Barcode)
                        CinephileBarcodeView(items: stats.barcodeData)
                            .padding(.horizontal, AppTheme.Spacing.pageMargin)

                        // Weekly Watch Arc
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                            SectionHeader(title: "Weekly Activity", icon: "calendar.badge.clock", iconColor: .orange)
                            WeeklyWatchArc(points: stats.watchTimeHistory, items: recentItems)
                                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        }

                        // Top Genres
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                            SectionHeader(title: "Top Genres", icon: "sparkles", iconColor: .indigo)
                            TopGenresView(items: Array(stats.genreDNA.prefix(10)))
                        }

                        // Decade Timeline (Release Era Distribution)
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                            SectionHeader(title: "Release Era", icon: "clock.arrow.circlepath", iconColor: AppTheme.Colors.accent)
                            DecadeTimeline(decades: stats.decadeDistribution)
                                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        }

                        // Top Studios
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                            SectionHeader(title: "Top Studios", icon: "building.2.fill", iconColor: .orange)
                            TopBrandsHorizontalView(items: stats.topRatedStudios, color: .orange, icon: "building.2.fill")
                        }

                        // Top Networks
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                            SectionHeader(title: "Top Networks", icon: "antenna.radiowaves.left.and.right", iconColor: .teal)
                            TopBrandsHorizontalView(items: stats.topRatedNetworks, color: .teal, icon: "antenna.radiowaves.left.and.right")
                        }
                    }
                    .padding(.vertical, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
                .navigationTitle("Cinephile Lab")
            }
        }
        .task { await fetchData() }
    }

    private func fetchData() async {
        let actor = LibraryStatsActor(modelContainer: modelContext.container)
        do {
            if let fullStats = try await actor.fetchCinephileData() {
                self.stats = fullStats
            }
        } catch {
            AppLogger.debug("Error fetching cinephile data: \(error)")
        }

        let cutoff = Date(timeIntervalSinceNow: -.days30)
        var descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { ($0.lastInteractionDate ?? cutoff) >= cutoff },
            sortBy: [SortDescriptor(\.lastInteractionDate, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        self.recentItems = (try? modelContext.fetch(descriptor)) ?? []

        try? await Task.sleep(nanoseconds: 350_000_000)
        withAnimation(.easeInOut(duration: 0.3)) { isLoading = false }
    }
}

// MARK: - Top Genres (Gallery Grid Tiles)

struct GalleryCardView: View {
    let name: String
    let value: Double
    let rank: Int
    let color: Color
    let icon: String

    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)

            ZStack {
                // Rank number shown by default
                Text(String(format: "%02d", rank))
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(color.gradient)
                    .opacity(isHovered ? 0.0 : 1.0)
                    .scaleEffect(isHovered ? 0.8 : 1.0)

                // Percentage shown on hover
                Text(String(format: "%.0f%%", value * 100))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .opacity(isHovered ? 1.0 : 0.0)
                    .scaleEffect(isHovered ? 1.0 : 1.2)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
            .frame(height: 32)

            Spacer(minLength: 0)

            Text(name)
                .font(AppTheme.Font.caption)
                .foregroundStyle(.primary.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 6)
                .frame(height: 28, alignment: .center)
        }
        .padding(.vertical, 8)
        .frame(width: 104, height: 90)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.cardFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isHovered
                        ? AnyShapeStyle(color.gradient)
                        : AnyShapeStyle(AppTheme.Colors.cardFill(for: colorScheme)),
                    lineWidth: isHovered ? 1.5 : 0.7
                )
        )
        .shadow(color: color.opacity(isHovered ? 0.12 : 0.0), radius: 6, x: 0, y: 3)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}

struct TopGenresView: View {
    let items: [(name: String, percentage: Double)]

    private var palette: [Color] {
        [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .mint, .red, .yellow]
    }

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
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(items.prefix(10).enumerated()), id: \.element.name) { idx, item in
                        let color = palette[idx % palette.count]
                        GalleryCardView(name: item.name, value: item.percentage, rank: idx + 1, color: color, icon: "film.fill")
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.vertical, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
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
                            let palette: [Color] = [.orange, .red, .purple, .blue, .teal, .indigo, .pink]
                            let index = abs(item.decade.hashValue) % palette.count
                            let baseColor = palette[index]
                            
                            DecadeDistributionRow(
                                decade: item.decade,
                                count: item.count,
                                percentage: Double(item.count) / Double(max(1, totalCount)),
                                relativeRatio: Double(item.count) / Double(max(1, maxCount)),
                                color: baseColor
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
    let color: Color

    var body: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            Text(decade)
                .font(AppTheme.Font.monoSmall)
                .foregroundStyle(.primary)
                .frame(width: 50, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.04))
                        .frame(height: 8)

                    Capsule()
                        .fill(color.gradient)
                        .frame(width: geo.size.width * relativeRatio, height: 8)
                }
            }
            .frame(height: 8)

            HStack(spacing: 4) {
                Text("\(count)")
                    .font(AppTheme.Font.monoSmall)
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
                        .font(AppTheme.Font.monoSmall)
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
                    .font(AppTheme.Font.smallBold)
                    .foregroundStyle(isToday ? AppTheme.Colors.accent : .secondary)
                Text("\(entry.dateNum)")
                    .font(AppTheme.Font.smallBold)
                    .foregroundStyle(isToday ? AppTheme.Colors.accent : .primary)
            }

            if entry.minutes > 0 {
                Text(formatWatchTimeMini(minutes: entry.minutes))
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(AppTheme.Colors.accent)

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
                    .font(AppTheme.Font.monoSmall)
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
                ? Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.03)
                : Color.primary.opacity(colorScheme == .dark ? 0.02 : 0.01)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                .stroke(
                    isToday ? Color.primary.opacity(0.3) : Color.primary.opacity(0.04),
                    lineWidth: isToday ? 1.0 : 0.5
                )
        )
    }
}

// MARK: - Top Brands Horizontal Scroll

struct TopBrandsHorizontalView: View {
    let items: [(name: String, score: Double)]
    let color: Color
    let icon: String

    var body: some View {
        if items.isEmpty {
            HStack {
                Spacer()
                Text("No statistics available")
                    .font(AppTheme.Font.body)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(height: 50)
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(items.prefix(10).enumerated()), id: \.element.name) { idx, item in
                        GalleryCardView(name: item.name, value: item.score, rank: idx + 1, color: color, icon: icon)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.vertical, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - Helpers

private func formatWatchTimeMini(minutes: Int) -> String {
    let hours = minutes / 60
    if hours > 0 { return "\(hours)h" }
    return "\(minutes)m"
}

struct CinephileLabSkeletonView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.section) {
                // 1. Cinephile Spectrum (Barcode) Skeleton
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 140, height: 16)
                        Spacer()
                    }
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 60)
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)

                // 2. Weekly Activity Arc Skeleton
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 120, height: 16)
                        Spacer()
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 180)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }

                // 3. Top Genres Skeleton
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 100, height: 16)
                        Spacer()
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<5, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 104, height: 90)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    }
                }

                // 4. Decade Timeline Skeleton
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 110, height: 16)
                        Spacer()
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 140)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }

                // 5. Top Studios/Networks Skeleton
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 130, height: 16)
                        Spacer()
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 180, height: 80)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    }
                }
            }
            .padding(.vertical, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .shimmering()
    }
}

#Preview("Cinephile Lab") {
    CinephileLabView()
}
