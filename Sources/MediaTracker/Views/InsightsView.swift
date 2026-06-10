import SwiftData
import SwiftUI

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme

    @State private var stats: LibraryStats?
    @State private var isLoading = true
    @State private var statsTask: Task<Void, Never>?
    var refreshID: Int = 0

    var body: some View {
        ZStack {
            AppTheme.Colors.background(for: colorScheme).ignoresSafeArea()

            if isLoading {
                InsightsSkeletonView()
            } else if let stats = stats {
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.section) {
                        // 1. Hero Stats
                        HeroStatGrid(stats: stats)
                            .padding(.horizontal, AppTheme.Spacing.pageMargin)

                        // 2. Top Genres
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                            SectionHeader(title: "Top Genres", icon: "sparkles", iconColor: .indigo)
                            TopGenresView(items: Array(stats.genreDNA.prefix(10)))
                        }

                        // 3. Taste DNA
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                            SectionHeader(title: "Taste DNA", icon: "heart.circle.fill", iconColor: .pink)
                            TasteBreakdownView(stats: stats)
                                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        }

                        // 4. Spectrum
                        CinephileBarcodeView(items: stats.barcodeData)
                            .padding(.horizontal, AppTheme.Spacing.pageMargin)

                        // 5. Studios & Networks
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                            SectionHeader(title: "Studios & Networks", icon: "building.2.fill", iconColor: .orange)
                            TopBrandsHorizontalView(items: stats.topRatedStudios, color: .orange, icon: "building.2.fill")
                            TopBrandsHorizontalView(items: stats.topRatedNetworks, color: .teal, icon: "antenna.radiowaves.left.and.right")
                        }

                        // 6. Cast & Crew
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                            SectionHeader(title: "Cast & Crew", icon: "person.3.fill", iconColor: .teal)
                            TalentLedgerView(stats: stats)
                        }
                    }
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .onAppear(perform: refreshData)
        .onChange(of: refreshID) { _, _ in refreshData() }
        .onDisappear {
            statsTask?.cancel()
            statsTask = nil
        }
    }

    private func refreshData() {
        statsTask?.cancel()
        statsTask = Task {
            let actor = LibraryStatsActor(modelContainer: modelContext.container)
            do {
                let result = try await actor.fetchStats(includeCinephileData: true)
                if Task.isCancelled { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.stats = result
                        self.isLoading = false
                    }
                }
            } catch {
                if !(error is CancellationError) {
                    AppLogger.debug("Error fetching stats: \(error)")
                }
            }
        }
    }
}

// MARK: - Hero Stats

struct HeroStatGrid: View {
    let stats: LibraryStats

    var body: some View {
        let total = stats.totalMovies + stats.totalTVShows
        let completed = stats.completedMovies + stats.completedTVShows
        let completionRate = total > 0 ? Double(completed) / Double(total) : 0
        let totalRated = stats.lovedCount + stats.likedCount + stats.dislikedCount
        let affinity = totalRated > 0 ? max(0, (3.0 * Double(stats.lovedCount) + 1.0 * Double(stats.likedCount) - 2.0 * Double(stats.dislikedCount)) / (3.0 * Double(totalRated))) : 0

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                StatCard(
                    icon: "film.stack.fill",
                    value: "\(total)",
                    label: "Titles",
                    detail: "\(stats.totalMovies) Movies · \(stats.totalTVShows) Shows",
                    color: .pink
                )
                StatCard(
                    icon: "clock.fill",
                    value: formatWatchTimeCompact(minutes: stats.totalWatchTimeMinutes),
                    label: "Watch Time",
                    detail: "\(stats.totalEpisodesWatched) episodes",
                    color: .orange
                )
                StatCard(
                    icon: "checkmark.circle.fill",
                    value: String(format: "%.0f%%", completionRate * 100),
                    label: "Completion",
                    detail: "\(completed)/\(total)",
                    color: .teal
                )
                StatCard(
                    icon: "heart.fill",
                    value: String(format: "%.0f%%", affinity * 100),
                    label: "Affinity",
                    detail: "\(stats.lovedCount)♥ · \(stats.likedCount)👍 · \(stats.dislikedCount)👎",
                    color: .purple
                )
            }
            .padding(.vertical, 8)
        }
    }
}

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let detail: String
    let color: Color

    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(color.opacity(0.8))

                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .frame(width: 240, height: 80, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color.opacity(colorScheme == .dark ? 0.08 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(color.opacity(colorScheme == .dark ? 0.2 : 0.12), lineWidth: 0.5)
                )
        )
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .shadow(color: color.opacity(isHovered ? 0.1 : 0), radius: 8, x: 0, y: 4)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.springSnappy) { isHovered = hovering }
        }
    }
}

// MARK: - Taste Breakdown

struct TasteBreakdownView: View {
    let stats: LibraryStats

    var body: some View {
        HStack(spacing: 12) {
            TasteBar(label: "Loved", count: stats.lovedCount, color: .pink)
            TasteBar(label: "Liked", count: stats.likedCount, color: .green)
            TasteBar(label: "Disliked", count: stats.dislikedCount, color: .red)
        }
    }
}

struct TasteBar: View {
    let label: String
    let count: Int
    let color: Color

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 6) {
            Text("\(count)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(colorScheme == .dark ? 0.08 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(color.opacity(0.15), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Top Genres

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
                        GalleryCardView(name: item.name, value: item.percentage, rank: idx + 1, color: color)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.vertical, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - Gallery Card

struct GalleryCardView: View {
    let name: String
    let value: Double
    let rank: Int
    let color: Color

    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            ZStack {
                Text(String(format: "%02d", rank))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(color.gradient)
                    .opacity(isHovered ? 0 : 1)

                Text(String(format: "%.0f%%", value * 100))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .opacity(isHovered ? 1 : 0)
            }
            .animation(AppTheme.Animation.springSnappy, value: isHovered)
            .frame(height: 30)

            Spacer(minLength: 0)

            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 6)
                .frame(height: 28, alignment: .center)
        }
        .padding(.vertical, 8)
        .frame(width: 100, height: 88)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.cardFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isHovered ? color : Color.clear, lineWidth: 1)
                .opacity(0.5)
        )
        .shadow(color: color.opacity(isHovered ? 0.1 : 0), radius: 6, x: 0, y: 3)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.springSnappy) { isHovered = hovering }
        }
    }
}

// MARK: - Top Brands Horizontal

struct TopBrandsHorizontalView: View {
    let items: [(name: String, score: Double)]
    let color: Color
    let icon: String

    var body: some View {
        if items.isEmpty {
            HStack {
                Spacer()
                Text("No data available")
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
                        GalleryCardView(name: item.name, value: item.score, rank: idx + 1, color: color)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.vertical, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - Barcode Spectrum

struct CinephileBarcodeView: View {
    let items: [BarcodeSlice]
    @State private var hoveredItem: BarcodeSlice?
    @State private var isScanning = false
    @State private var scanPosition: CGFloat = 0.0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                HStack {
                    Text("SPECTRUM")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                        .kerning(1.2)

                    Spacer()

                    if let item = hoveredItem {
                        HStack(spacing: 4) {
                            Text(item.title)
                                .font(AppTheme.Font.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("·")
                                .foregroundStyle(.secondary)
                            let isNone = item.tasteValue == TasteValue.none.rawValue
                            Text(isNone ? "UNRATED" : item.tasteValue.uppercased())
                                .font(AppTheme.Font.caption2)
                                .foregroundStyle({
                                    guard let taste = TasteValue(rawValue: item.tasteValue) else { return Color.secondary }
                                    return taste.color
                                }())
                        }
                        .transition(.opacity)
                    } else {
                        Text("HOVER TO SCAN")
                            .font(AppTheme.Font.mono)
                            .foregroundStyle(.secondary.opacity(0.4))
                    }
                }

                let validItems = items.filter { $0.themeColorHex != nil }
                if validItems.isEmpty {
                    HStack {
                        Spacer()
                        Text("Add rated or themed titles to generate spectrum")
                            .font(AppTheme.Font.body)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(height: 32)
                } else {
                    ZStack(alignment: .leading) {
                        HStack(spacing: 2) {
                            Spacer(minLength: 0)
                            ForEach(validItems.prefix(100)) { item in
                                let isCurrentHovered = hoveredItem?.id == item.id
                                let barColor: Color = {
                                    if let hex = item.themeColorHex, let c = Color(hex: hex) { return c }
                                    guard let taste = TasteValue(rawValue: item.tasteValue) else { return .primary.opacity(0.15) }
                                    return taste.color
                                }()

                                RoundedRectangle(cornerRadius: 1.0)
                                    .fill(isCurrentHovered ? barColor : barColor.opacity(0.8))
                                    .frame(height: 32)
                                    .frame(minWidth: 1.5, maxWidth: 6)
                                    .scaleEffect(y: isCurrentHovered ? 1.15 : 1.0)
                                    .shadow(color: isCurrentHovered ? barColor.opacity(0.5) : .clear, radius: isCurrentHovered ? 6 : 0)
                                    .contentShape(Rectangle())
                                    .onHover { isHovered in
                                        withAnimation(AppTheme.Animation.springSnappy) {
                                            if isHovered { hoveredItem = item; isScanning = true }
                                            else if hoveredItem?.id == item.id { hoveredItem = nil; isScanning = false }
                                        }
                                    }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(height: 44)

                        if isScanning {
                            GeometryReader { geo in
                                AppTheme.Colors.accent.opacity(0.4)
                                    .frame(width: 2, height: 44)
                                    .shadow(color: AppTheme.Colors.accent.opacity(0.5), radius: 6)
                                    .offset(x: scanPosition * geo.size.width)
                                    .onAppear {
                                        scanPosition = 0.0
                                        withAnimation(Animation.linear(duration: 2.2).repeatForever(autoreverses: true)) {
                                            scanPosition = 1.0
                                        }
                                    }
                                    .onDisappear { scanPosition = 0.0 }
                            }
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Cast & Crew

struct TalentLedgerView: View {
    let stats: LibraryStats

    var body: some View {
        VStack(spacing: AppTheme.Spacing.section) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text("TOP RATED CAST")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                if stats.topRatedActors.isEmpty {
                    DashboardCard {
                        HStack {
                            Spacer()
                            Text("No actor data")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(height: 80)
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(Array(stats.topRatedActors.prefix(10).enumerated()), id: \.element.name) { index, person in
                                TalentCardView(person: person, rank: index + 1, color: .orange)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        .padding(.vertical, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text("TOP RATED CREATORS")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                if stats.topRatedCreators.isEmpty {
                    DashboardCard {
                        HStack {
                            Spacer()
                            Text("No creator data")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(height: 80)
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(Array(stats.topRatedCreators.prefix(10).enumerated()), id: \.element.name) { index, person in
                                TalentCardView(person: person, rank: index + 1, color: .green)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        .padding(.vertical, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
    }
}

struct TalentCardView: View {
    let person: VisualPersonStat
    let rank: Int
    let color: Color

    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let urlString = person.profileURL, let url = URL(string: urlString) {
                    CachedImage(url: url, targetSize: CGSize(width: 44, height: 64), priority: .low, themeColor: color) {
                        ProgressView().controlSize(.small)
                    }
                    .scaledToFill()
                    .frame(width: 44, height: 64)
                } else {
                    ZStack {
                        Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.03)
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 18))
                    }
                    .frame(width: 44, height: 64)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                ZStack(alignment: .leading) {
                    Text(String(format: "%02d", rank))
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(color.gradient)
                        .opacity(isHovered ? 0 : 1)

                    Text(String(format: "%.0f%%", person.score * 100))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                        .opacity(isHovered ? 1 : 0)
                }
                .animation(AppTheme.Animation.springSnappy, value: isHovered)
                .frame(height: 14)

                Text(person.name)
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            .padding(.trailing, 8)

            Spacer(minLength: 0)
        }
        .frame(width: 180, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.cardFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isHovered ? color : Color.clear, lineWidth: 1)
                .opacity(0.5)
        )
        .shadow(color: color.opacity(isHovered ? 0.1 : 0), radius: 6, x: 0, y: 3)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.springSnappy) { isHovered = hovering }
        }
    }
}

// MARK: - Dashboard Card

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
            .background(AppTheme.Colors.cardFill(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), lineWidth: 0.5)
            )
    }
}

// MARK: - Skeleton

struct InsightsSkeletonView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.section) {
                // Hero skeleton
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                                .frame(width: 240, height: 80)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }

                // Genres skeleton
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 100, height: 16)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<5, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 100, height: 88)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    }
                }

                // Barcode skeleton
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 120, height: 16)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 60)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }

                // Talent skeleton
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 140, height: 16)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<5, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 180, height: 64)
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

// MARK: - Helpers

func formatWatchTimeCompact(minutes: Int) -> String {
    let days = minutes / 1440
    let hours = (minutes % 1440) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    return "\(hours)h \(minutes % 60)m"
}
