import Charts
import SwiftData
import SwiftUI

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var stats: LibraryStats?
    @State private var isLoading = true

    private enum InsightsTab: String, CaseIterable, Identifiable {
        case taste = "Taste & Affinity"
        case activity = "Activity & Talent"
        
        var id: String { self.rawValue }
    }
    
    @State private var selectedTab: InsightsTab = .taste
    @Namespace private var tabNamespace

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()
            
            // Atmospheric gradient glow
            GeometryReader { geo in
                RadialGradient(
                    colors: [Color.accentColor.opacity(colorScheme == .dark ? 0.14 : 0.05), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: min(geo.size.width, geo.size.height) * 0.9
                )
                .ignoresSafeArea()
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 44) {
                    if isLoading {
                        loadingView
                    } else if let stats = stats {
                        // Empty space to push content below native title bar
                        Spacer()
                            .frame(height: 12)
                        
                        mainContent(stats: stats)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 16)
                .padding(.bottom, 110) // Extra padding so content isn't blocked by floating bar
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            
            if !isLoading && stats != nil {
                floatingTabBar
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            refreshData()
        }
    }

    @ViewBuilder
    private func mainContent(stats: LibraryStats) -> some View {
        switch selectedTab {
        case .taste:
            tasteTabContent(stats: stats)
        case .activity:
            activityTabContent(stats: stats)
        }
    }

    @ViewBuilder
    private func tasteTabContent(stats: LibraryStats) -> some View {
        cinephilePassportCard(stats: stats)
        
        cinemaDNADashboard(stats: stats)
        
        decadeFilmStripSection(stats: stats)
        
        productionDeckSection(stats: stats)
    }

    @ViewBuilder
    private func activityTabContent(stats: LibraryStats) -> some View {
        watchTrendsSection(stats: stats)
        
        hallOfFameSection(stats: stats)
        
        masterySection(stats: stats)
    }

    private var floatingTabBar: some View {
        HStack(spacing: 4) {
            ForEach(InsightsTab.allCases) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selectedTab = tab
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: tab == .taste ? "sparkles" : "person.3.fill")
                            .font(.system(size: 12, weight: .semibold))
                        
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        ZStack {
                            if selectedTab == tab {
                                Capsule()
                                    .fill(Color.accentColor)
                                    .matchedGeometryEffect(id: "activeTab", in: tabNamespace)
                                    .shadow(color: Color.accentColor.opacity(0.35), radius: 6, x: 0, y: 3)
                            }
                        }
                    )
                    .foregroundStyle(
                        selectedTab == tab
                        ? Color.white
                        : .primary.opacity(0.65)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.1), radius: 10, x: 0, y: 5)
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func premiumCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.thinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.04), radius: 10, x: 0, y: 4)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 0.5)
            }
    }


    private func refreshData() {
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            let actor = LibraryStatsActor(modelContainer: modelContext.container)
            let result = await actor.fetchStats()
            await MainActor.run {
                withAnimation(.smooth) {
                    self.stats = result
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Sections

    // MARK: - Cinema DNA Dashboard & Calibration

    // MARK: - Archetype & Passport Structures

    private struct ArchetypeData {
        let title: String
        let icon: String
        let color: Color
        let description: String
    }
    
    private func calculateArchetype(stats: LibraryStats) -> ArchetypeData {
        let topGenre = stats.topRatedGenres.first?.0.lowercased() ?? ""
        
        if topGenre.contains("action") || topGenre.contains("adventure") || topGenre.contains("thriller") {
            return ArchetypeData(
                title: "The Thrillseeker",
                icon: "shield.fill",
                color: .red,
                description: "Driven by adrenaline-pumping sequences and fast-paced narratives. Your library leans toward action, adventure, and high-stakes thrillers."
            )
        } else if topGenre.contains("sci-fi") || topGenre.contains("science") || topGenre.contains("fantasy") {
            return ArchetypeData(
                title: "The Sci-Fi Visionary",
                icon: "sparkles",
                color: .purple,
                description: "Captivated by alternate realities, space exploration, and future technologies. You love to explore what lies beyond the horizon of human imagination."
            )
        } else if topGenre.contains("drama") || topGenre.contains("romance") {
            return ArchetypeData(
                title: "The Indie Purist",
                icon: "heart.text.square.fill",
                color: .pink,
                description: "Deeply moved by character studies, emotional complexities, and artistic narratives. You value acting performance and writing depth over blockbusters."
            )
        } else if topGenre.contains("comedy") {
            return ArchetypeData(
                title: "The Comedy Lover",
                icon: "face.smiling.fill",
                color: .yellow,
                description: "Believer that cinema should make us smile. You seek out lighthearted storytelling, witty dialogue, and feel-good stories."
            )
        } else if topGenre.contains("animation") || topGenre.contains("family") {
            return ArchetypeData(
                title: "The Animation Enthusiast",
                icon: "paintpalette.fill",
                color: .blue,
                description: "Driven by visual storytelling, hand-drawn art, and family-friendly adventures. You appreciate the craftsmanship of animation."
            )
        } else if topGenre.contains("documentary") || topGenre.contains("history") {
            return ArchetypeData(
                title: "The Archivist",
                icon: "scroll.fill",
                color: .orange,
                description: "Fascinated by real-world histories, human facts, and documentaries. You treat cinema as a window to learn about past events and truths."
            )
        } else if topGenre.contains("crime") || topGenre.contains("mystery") || topGenre.contains("horror") {
            return ArchetypeData(
                title: "The Midnight Detective",
                icon: "flashlight.on.fill",
                color: .indigo,
                description: "Drawn to dark hallways, psychological puzzles, and suspenseful scares. You thrive on horror, crime, and suspenseful mystery."
            )
        } else {
            return ArchetypeData(
                title: "The Cinema Explorer",
                icon: "map.fill",
                color: .green,
                description: "A balanced generalist who appreciates all aspects of filmmaking. You enjoy crossing genre boundaries and finding hidden gems."
            )
        }
    }

    @ViewBuilder
    private func cinephilePassportCard(stats: LibraryStats) -> some View {
        let totalLibrary = stats.totalMovies + stats.totalTVShows
        let rank: String = {
            if totalLibrary >= 100 { return "ELITE CURATOR" }
            if totalLibrary >= 50 { return "MARATHON LEGEND" }
            if totalLibrary >= 20 { return "ACTIVE EXPLORER" }
            return "CINEMA NOVICE"
        }()
        
        let archetype = calculateArchetype(stats: stats)
        
        premiumCard {
            HStack(spacing: 28) {
                // Left Column: Avatar & Rank
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(archetype.color.gradient.opacity(0.18))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: archetype.icon)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(archetype.color.gradient)
                            .shadow(color: archetype.color.opacity(0.3), radius: 5)
                    }
                    
                    Text(rank)
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(archetype.color.gradient)
                        .clipShape(Capsule())
                        .shadow(color: archetype.color.opacity(0.3), radius: 4)
                }
                .frame(width: 120)
                
                // Divider
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)
                    .frame(maxHeight: 110)
                
                // Right Column: Passport details
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("CINEPHILE PASSPORT")
                            .font(.system(size: 10, weight: .black))
                            .kerning(2.0)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                    
                    // Detail Grid
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        passportField(label: "PASSPORT NO.", value: String(format: "MT-%05d-%02d", totalLibrary, stats.totalEpisodesWatched % 100))
                        passportField(label: "ARCHETYPE", value: archetype.title.uppercased())
                        passportField(label: "TOTAL WATCHED", value: "\(totalLibrary) TITLES")
                        passportField(label: "CINEMA EXP", value: formatWatchTimeSimple(minutes: stats.totalWatchTimeMinutes).uppercased())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func passportField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.secondary.opacity(0.7))
                .kerning(1.0)
            
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func decadeFilmStripSection(stats: LibraryStats) -> some View {
        if !stats.decadeDistribution.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "film")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.accentColor.gradient)
                    Text("DECADE DENSITY (FILM STRIP)")
                        .font(.system(size: 10, weight: .black))
                        .kerning(1.5)
                        .foregroundStyle(.secondary)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(stats.decadeDistribution) { point in
                            VStack(spacing: 6) {
                                // Top sprockets
                                HStack(spacing: 6) {
                                    ForEach(0..<6) { _ in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.primary.opacity(0.2))
                                            .frame(width: 6, height: 4)
                                    }
                                }
                                .padding(.top, 4)
                                
                                Spacer()
                                
                                VStack(spacing: 2) {
                                    Text(point.decade)
                                        .font(.system(size: 16, weight: .black, design: .rounded))
                                        .foregroundStyle(.primary)
                                    
                                    Text("\(point.count) titles")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                // Bottom sprockets
                                HStack(spacing: 6) {
                                    ForEach(0..<6) { _ in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.primary.opacity(0.2))
                                            .frame(width: 6, height: 4)
                                    }
                                }
                                .padding(.bottom, 4)
                            }
                            .frame(width: 100, height: 110)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func cinemaDNADashboard(stats: LibraryStats) -> some View {
        HStack(alignment: .top, spacing: 24) {
            // Left Panel: DNA Profile (Identity + Radar Chart)
            dnaProfileCard(stats: stats)
                .frame(maxWidth: .infinity)
            
            // Right Panel: Taste Calibration (Donut Chart + Stats)
            tasteCalibrationCard(stats: stats)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func dnaProfileCard(stats: LibraryStats) -> some View {
        let archetype = calculateArchetype(stats: stats)

        premiumCard {
            VStack(alignment: .leading, spacing: 20) {
                sectionLabel("CINEMA DNA PROFILE", icon: "sparkles")
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(archetype.title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(archetype.color.gradient)
                    
                    Text(archetype.description)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 10)
                
                RadarChartView(data: stats.genreDNA, accentColor: archetype.color)
                    .frame(height: 250)
            }
        }
    }

    @ViewBuilder
    private func tasteCalibrationCard(stats: LibraryStats) -> some View {
        let totalLibrary = stats.totalMovies + stats.totalTVShows
        let leftoverCount = max(0, totalLibrary - (stats.lovedCount + stats.likedCount + stats.dislikedCount))
        
        let segments = [
            TasteSegment(label: "Loved", count: stats.lovedCount, color: Color.semanticGreen(for: colorScheme)),
            TasteSegment(label: "Liked", count: stats.likedCount, color: .yellow),
            TasteSegment(label: "Disliked", count: stats.dislikedCount, color: Color.semanticRed(for: colorScheme)),
            TasteSegment(label: "Unrated", count: leftoverCount, color: colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
        ].filter { $0.count > 0 }

        premiumCard {
            VStack(alignment: .leading, spacing: 20) {
                sectionLabel("TASTE CALIBRATION", icon: "chart.pie.fill")
                
                HStack(alignment: .center, spacing: 24) {
                    // Donut Chart
                    ZStack {
                        if totalLibrary > 0 {
                            Chart(segments) { segment in
                                SectorMark(
                                    angle: .value("Count", segment.count),
                                    innerRadius: .ratio(0.68),
                                    angularInset: 2.5
                                )
                                .foregroundStyle(segment.color)
                                .cornerRadius(5)
                            }
                            .frame(width: 140, height: 140)

                            VStack(spacing: 2) {
                                Text("\(totalLibrary)")
                                    .font(.system(size: 24, weight: .black, design: .rounded))
                                    .foregroundStyle(.primary)
                                Text("TITLES")
                                    .font(.system(size: 8, weight: .black))
                                    .kerning(1.5)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "chart.pie.fill")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                Text("No Titles")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: 150, height: 150)
                    
                    // Legend
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(segments) { segment in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(segment.color)
                                    .frame(width: 8, height: 8)
                                
                                Text(segment.label)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                Text("\(segment.count)")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.primary)
                                
                                if totalLibrary > 0 {
                                    Text("(\(Int(Double(segment.count) / Double(totalLibrary) * 100))%)")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                
                Divider()
                    .opacity(0.3)
                
                HStack(spacing: 12) {
                    // Watch Time
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "hourglass.badge.ellipsis")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.orange.gradient)
                            Text("WATCH TIME")
                                .font(.system(size: 9, weight: .black))
                                .kerning(1.0)
                                .foregroundStyle(.secondary)
                        }
                        Text(formatWatchTimeSimple(minutes: stats.totalWatchTimeMinutes))
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                        .frame(height: 36)
                        .opacity(0.4)
                    
                    // Episodes Watched
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.square.stack.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.blue.gradient)
                            Text("EPISODES WATCHED")
                                .font(.system(size: 9, weight: .black))
                                .kerning(1.0)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(stats.totalEpisodesWatched)")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Watch Trends Section

    private var mockWatchHistory: [WatchTimePoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).map { i in
            let date = calendar.date(byAdding: .day, value: -i, to: today) ?? today
            let minutes = [45, 90, 0, 120, 60, 30, 75][i]
            return WatchTimePoint(date: date, minutes: minutes)
        }.sorted { $0.date < $1.date }
    }

    @ViewBuilder
    private func watchTrendsSection(stats: LibraryStats) -> some View {
        let isPlaceholder = stats.watchTimeHistory.isEmpty
        let historyData: [WatchTimePoint] = {
            if isPlaceholder { return mockWatchHistory }
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            return (0..<7).map { i in
                let date = calendar.date(byAdding: .day, value: -i, to: today) ?? today
                let mins = stats.watchTimeHistory.first(where: { calendar.isDate($0.date, inSameDayAs: date) })?.minutes ?? 0
                return WatchTimePoint(date: date, minutes: mins)
            }.sorted { $0.date < $1.date }
        }()
        let lastPoint = historyData.last
        
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                sectionLabel("ACTIVITY INDEX", icon: "chart.xyaxis.line")

                HStack(spacing: 4) {
                    PulsatingDot()
                    Text("LIVE FEED")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.09))
                .clipShape(Capsule())
                
                Spacer()
                if isPlaceholder {
                    Text("PREVIEW STATE")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            premiumCard {
                ZStack {
                    Chart {
                        ForEach(historyData) { point in
                            AreaMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("", point.minutes)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor.opacity(isPlaceholder ? 0.07 : 0.22),
                                        Color.accentColor.opacity(0.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("", point.minutes)
                            )
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(Color.accentColor.opacity(isPlaceholder ? 0.4 : 1.0))

                            if point.id == lastPoint?.id {
                                PointMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value("", point.minutes)
                                )
                                .foregroundStyle(Color.accentColor)
                                .symbolSize(100)
                                .annotation(position: .overlay, alignment: .center, spacing: 0) {
                                    PulsatingChartNode(color: Color.accentColor)
                                }
                            } else {
                                PointMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value("", point.minutes)
                                )
                                .foregroundStyle(Color.accentColor.opacity(isPlaceholder ? 0.4 : 1.0))
                                .symbolSize(32)
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 1)) { value in
                            if value.as(Date.self) != nil {
                                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            AxisGridLine()
                                .foregroundStyle(Color.primary.opacity(0.04))
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            if let mins = value.as(Int.self) {
                                AxisValueLabel("\(mins)")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            AxisGridLine()
                                .foregroundStyle(Color.primary.opacity(0.04))
                        }
                    }
                    .frame(height: 300)

                    if isPlaceholder {
                        VStack(spacing: 10) {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.title2)
                                .foregroundStyle(.secondary.opacity(0.6))
                            Text("Viewing activity trends will appear as you watch content.")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(20)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func hallOfFameSection(stats: LibraryStats) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            personCarousel(title: "TOP ACTORS", people: stats.topRatedActors, color: .orange)
            personCarousel(title: "TOP CREATORS & DIRECTORS", people: stats.topRatedCreators, color: .green)
        }
    }

    @ViewBuilder
    private func productionDeckSection(stats: LibraryStats) -> some View {
        VStack(alignment: .leading, spacing: 36) {
            bentoGenreGrid(data: stats.topRatedGenres)

            HStack(alignment: .top, spacing: 32) {
                filmStripStudiosList(data: stats.topRatedStudios)
                    .frame(maxWidth: .infinity)
                
                broadcastNetworksGrid(data: stats.topRatedNetworks)
                    .frame(maxWidth: .infinity)
            }

            languagePillsRow(data: stats.topRatedLanguages)
        }
    }

    @ViewBuilder
    private func masterySection(stats: LibraryStats) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("MASTERED COLLECTIONS", icon: "checkmark.seal.fill")

            HStack(spacing: 20) {
                MasteryCardView(
                    title: "Movies", label: nil, value: nil, subtitle: nil,
                    current: stats.completedMovies, total: stats.totalMovies,
                    color: .blue, colorScheme: colorScheme)
                
                MasteryCardView(
                    title: "TV Shows", label: nil, value: nil, subtitle: nil,
                    current: stats.completedTVShows, total: stats.totalTVShows,
                    color: .purple, colorScheme: colorScheme)
                
                MasteryCardView(
                    title: nil, label: "EPISODES", value: "\(stats.totalEpisodesWatched)", subtitle: "WATCHED",
                    current: 0, total: 0,
                    color: .orange, colorScheme: colorScheme)
            }
        }
    }

    // MARK: - Shared Label Helper

    private func sectionLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.accentColor.gradient)
            Text(text)
                .font(.system(size: 10, weight: .black))
                .kerning(1.5)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Genre & Production Components

    private func emoji(forGenre genre: String) -> String {
        let lower = genre.lowercased()
        if lower.contains("action") { return "⚔️" }
        if lower.contains("adventure") { return "🗺️" }
        if lower.contains("animation") { return "🎨" }
        if lower.contains("comedy") { return "😂" }
        if lower.contains("crime") { return "🕵️‍♂️" }
        if lower.contains("documentary") { return "📹" }
        if lower.contains("drama") { return "🎭" }
        if lower.contains("family") { return "👨‍👩‍👧‍👦" }
        if lower.contains("fantasy") { return "🦄" }
        if lower.contains("history") { return "📜" }
        if lower.contains("horror") { return "👻" }
        if lower.contains("music") { return "🎵" }
        if lower.contains("mystery") { return "🔍" }
        if lower.contains("romance") { return "💖" }
        if lower.contains("sci-fi") || lower.contains("science") { return "🚀" }
        if lower.contains("thriller") { return "⚡" }
        if lower.contains("war") { return "🪖" }
        if lower.contains("western") { return "🤠" }
        return "🎬"
    }

    private func networkColor(name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("hbo") { return Color(red: 0.35, green: 0.1, blue: 0.8) }
        if lower.contains("netflix") { return Color(red: 0.89, green: 0.04, blue: 0.1) }
        if lower.contains("disney") { return Color(red: 0.0, green: 0.35, blue: 0.8) }
        if lower.contains("apple tv") { return Color.primary }
        if lower.contains("amazon") || lower.contains("prime") { return Color(red: 0.0, green: 0.65, blue: 0.9) }
        return Color.indigo
    }

    private func flag(forLanguage lang: String) -> String {
        let lower = lang.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch lower {
        case "english", "en", "us", "uk": return "🇺🇸"
        case "japanese", "ja", "jp", "日本語": return "🇯🇵"
        case "french", "fr", "français": return "🇫🇷"
        case "korean", "ko", "kr", "한국어": return "🇰🇷"
        case "spanish", "es", "español": return "🇪🇸"
        case "german", "de", "deutsch": return "🇩🇪"
        case "italian", "it", "italiano": return "🇮🇹"
        case "chinese", "zh", "cn", "中文": return "🇨🇳"
        default: break
        }
        
        let indianLanguages = ["telugu", "te", "తెలుగు", "hindi", "hi", "हिन्दी", "tamil", "ta", "தமிழ்", "malayalam", "ml", "മലയാളം", "kannada", "kn", "ಕನ್ನಡ"]
        for indLang in indianLanguages {
            if lower == indLang || lower.hasPrefix(indLang + "-") || lower.hasPrefix(indLang + "_") {
                return "🇮🇳"
            }
        }
        
        if lower.contains("telugu") || lower.contains("తెలుగు") ||
           lower.contains("hindi") || lower.contains("हिन्दी") ||
           lower.contains("tamil") || lower.contains("தமிழ்") ||
           lower.contains("malayalam") || lower.contains("മലയാളം") ||
           lower.contains("kannada") || lower.contains("ಕನ್ನಡ") {
            return "🇮🇳"
        }
        
        if lower.contains("english") { return "🇺🇸" }
        if lower.contains("japanese") || lower.contains("nihongo") { return "🇯🇵" }
        if lower.contains("french") || lower.contains("franc") { return "🇫🇷" }
        if lower.contains("korean") || lower.contains("hangul") { return "🇰🇷" }
        if lower.contains("spanish") || lower.contains("espan") { return "🇪🇸" }
        if lower.contains("german") || lower.contains("deutsch") { return "🇩🇪" }
        if lower.contains("italian") { return "🇮🇹" }
        if lower.contains("chinese") { return "🇨🇳" }
        
        let indCodes = ["te", "hi", "ta", "ml", "kn"]
        for code in indCodes {
            if lower == code || lower.hasPrefix(code + "-") || lower.hasPrefix(code + "_") {
                return "🇮🇳"
            }
        }
        
        return "🌐"
    }

    @ViewBuilder
    private func bentoGenreGrid(data: [(name: String, score: Double)]) -> some View {
        if !data.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 13, weight: .bold))
                    Text("HIGHEST RATED GENRES")
                        .font(.system(size: 11, weight: .black))
                        .kerning(1.5)
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Array(data.enumerated()), id: \.element.name) { index, item in
                            VisualGenreCard(rank: index + 1, name: item.name, score: item.score, color: .blue)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func filmStripStudiosList(data: [(name: String, score: Double)]) -> some View {
        if !data.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "film.fill")
                        .foregroundStyle(.purple)
                        .font(.system(size: 13, weight: .bold))
                    Text("TOP STUDIOS")
                        .font(.system(size: 11, weight: .black))
                        .kerning(1.5)
                        .foregroundStyle(.secondary)
                }

                premiumCard {
                    VStack(spacing: 12) {
                        ForEach(Array(data.prefix(6).enumerated()), id: \.element.0) { index, item in
                            let rank = index + 1
                            HStack(spacing: 14) {
                                // Film sprocket decoration
                                VStack(spacing: 4) {
                                    ForEach(0..<3) { _ in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.primary.opacity(0.18))
                                            .frame(width: 4, height: 5)
                                    }
                                }
                                .padding(.horizontal, 3)
                                
                                Text("#\(rank)")
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .foregroundStyle(.purple)
                                    .frame(width: 28, alignment: .leading)
                                
                                Text(item.0)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                // Dot meter (spacious and clean)
                                HStack(spacing: 3) {
                                    let activeDots = Int(round(item.1 * 10))
                                    ForEach(0..<10) { dotIdx in
                                        Circle()
                                            .fill(dotIdx < activeDots ? Color.purple : Color.primary.opacity(0.06))
                                            .frame(width: 5, height: 5)
                                    }
                                }
                                
                                Text("\(Int(item.1 * 100))%")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.purple)
                                    .frame(width: 38, alignment: .trailing)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                Color.purple.opacity(rank == 1 ? 0.08 : 0.0)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            
                            if rank < min(data.count, 6) {
                                Divider().opacity(0.3)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func broadcastNetworksGrid(data: [(name: String, score: Double)]) -> some View {
        if !data.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "tv.fill")
                        .foregroundStyle(.indigo)
                        .font(.system(size: 13, weight: .bold))
                    Text("TOP NETWORKS")
                        .font(.system(size: 11, weight: .black))
                        .kerning(1.5)
                        .foregroundStyle(.secondary)
                }

                premiumCard {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        ForEach(Array(data.prefix(6).enumerated()), id: \.element.0) { index, item in
                            let rank = index + 1
                            let nColor = networkColor(name: item.0)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .center) {
                                    Text("#\(rank)")
                                        .font(.system(size: 9, weight: .black, design: .rounded))
                                        .foregroundStyle(rank == 1 ? Color.white : nColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(rank == 1 ? nColor : nColor.opacity(0.12))
                                        .clipShape(Capsule())
                                    Spacer()
                                }
                                
                                Text(item.0)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                
                                HStack(alignment: .firstTextBaseline, spacing: 2) {
                                    Text("\(Int(item.1 * 100))%")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(nColor)
                                    Text("SCORE")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(
                                ZStack {
                                    Color.secondary.opacity(0.02)
                                    RadialGradient(
                                        colors: [nColor.opacity(0.06), .clear],
                                        center: .bottomTrailing,
                                        startRadius: 0,
                                        endRadius: 50
                                    )
                                }
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(nColor.opacity(rank == 1 ? 0.35 : 0.08), lineWidth: rank == 1 ? 1.0 : 0.5)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func languagePillsRow(data: [(name: String, score: Double)]) -> some View {
        if !data.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(.mint)
                        .font(.system(size: 13, weight: .bold))
                    Text("TOP LANGUAGES")
                        .font(.system(size: 11, weight: .black))
                        .kerning(1.5)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    ForEach(Array(data.prefix(6).enumerated()), id: \.element.0) { index, item in
                        let rank = index + 1
                        HStack(spacing: 8) {
                            Text(flag(forLanguage: item.0))
                                .font(.system(size: 16))
                            
                            Text(item.0)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            
                            Text("\(Int(item.1 * 100))%")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.mint)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.mint.opacity(0.13))
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(Color.mint.opacity(rank == 1 ? 0.4 : 0.08), lineWidth: rank == 1 ? 1.0 : 0.5)
                        }
                        .shadow(color: Color.black.opacity(0.02), radius: 4, y: 2)
                    }
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func personCarousel(title: String, people: [VisualPersonStat], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: title.contains("ACTORS") ? "person.3.fill" : "crown.fill")
                    .foregroundStyle(color)
                    .font(.system(size: 13, weight: .bold))
                
                Text(title)
                    .font(.system(size: 11, weight: .black))
                    .kerning(1.5)
                    .foregroundStyle(.secondary)
            }
            
            if people.isEmpty {
                premiumCard {
                    HStack {
                        Spacer()
                        Text("No entries available")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 24)
                        Spacer()
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(Array(people.enumerated()), id: \.element.name) { index, person in
                            VisualPersonCard(rank: index + 1, person: person, color: color)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

// MARK: - Carousel Cards

private struct VisualGenreCard: View {
    let rank: Int
    let name: String
    let score: Double
    let color: Color
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("#\(rank)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(rank == 1 ? .white : color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(rank == 1 ? color : color.opacity(0.12))
                    .clipShape(Capsule())
                
                Spacer()
                
                Text(emoji(forGenre: name))
                    .font(.system(size: 26))
            }
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name.uppercased())
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(score * 100))%")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                    Text("AFFINITY")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            
            GeometryReader { geo in
                Capsule()
                    .fill(Color.primary.opacity(0.06))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color.gradient)
                            .frame(width: geo.size.width * CGFloat(score))
                    }
            }
            .frame(height: 4)
        }
        .padding(16)
        .frame(width: 170, height: 130)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.15 : 0.03), radius: 6, x: 0, y: 3)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(rank == 1 ? color.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: rank == 1 ? 1.2 : 0.5)
        }
    }
    
    private func emoji(forGenre genre: String) -> String {
        let lower = genre.lowercased()
        if lower.contains("action") { return "⚔️" }
        if lower.contains("adventure") { return "🗺️" }
        if lower.contains("animation") { return "🎨" }
        if lower.contains("comedy") { return "😂" }
        if lower.contains("crime") { return "🕵️‍♂️" }
        if lower.contains("documentary") { return "📹" }
        if lower.contains("drama") { return "🎭" }
        if lower.contains("family") { return "👨‍👩‍👧‍👦" }
        if lower.contains("fantasy") { return "🦄" }
        if lower.contains("history") { return "📜" }
        if lower.contains("horror") { return "👻" }
        if lower.contains("music") { return "🎵" }
        if lower.contains("mystery") { return "🔍" }
        if lower.contains("romance") { return "💖" }
        if lower.contains("sci-fi") || lower.contains("science") { return "🚀" }
        if lower.contains("thriller") { return "⚡" }
        if lower.contains("war") { return "🪖" }
        if lower.contains("western") { return "🤠" }
        return "🎬"
    }
}

private struct VisualPersonCard: View {
    let rank: Int
    let person: VisualPersonStat
    let color: Color
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let urlString = person.profileURL, let url = URL(string: urlString) {
                        CachedImage(url: url, targetSize: CGSize(width: 240, height: 360), priority: .normal) { _ in
                        } placeholder: {
                            Color.secondary.opacity(0.08)
                                .overlay {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(.secondary.opacity(0.6))
                                }
                        }
                        .scaledToFill()
                    } else {
                        Color.secondary.opacity(0.08)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.secondary.opacity(0.6))
                            }
                    }
                }
                .frame(width: 120, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .clipped()
                
                Text("#\(rank)")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.gradient)
                    .clipShape(Capsule())
                    .shadow(color: color.opacity(0.4), radius: 4, x: 0, y: 2)
                    .offset(x: 10, y: 10)
            }
            .frame(width: 120, height: 180)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(rank == 1 ? color.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: rank == 1 ? 1.0 : 0.5)
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.15 : 0.03), radius: 4, x: 0, y: 2)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(person.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .leading)
                
                HStack(spacing: 4) {
                    Text("\(person.count) titles")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .foregroundStyle(.secondary.opacity(0.4))
                        
                    Text("\(Int(person.score * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

extension InsightsView {

    // MARK: - Helpers

    private func formatWatchTimeSimple(minutes: Int) -> String {
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        return "\(hours)h \(minutes % 60)m"
    }

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView().controlSize(.large)
            Text("EXTRACTING CINEMA DNA")
                .font(.system(size: 13, weight: .black))
                .kerning(2.5)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 480)
    }
}

// MARK: - Dedicated Views for Premium Aesthetics

private struct MasteryCardView: View {
    let title: String?
    let label: String?
    let value: String?
    let subtitle: String?
    let current: Int
    let total: Int
    let color: Color
    let colorScheme: ColorScheme
    
    var body: some View {
        HStack(spacing: 20) {
            if let title = title {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title.uppercased())
                        .font(.system(size: 12, weight: .black))
                        .kerning(2.0)
                        .foregroundStyle(.secondary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(current)")
                            .font(.system(size: 38, weight: .black, design: .rounded))
                        Text("/ \(total)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("COMPLETED")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                let pct = total > 0 ? Double(current) / Double(total) : 0.0
                ZStack {
                    Circle()
                        .stroke(color.opacity(0.12), lineWidth: 7)
                        .frame(width: 68, height: 68)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(pct))
                        .stroke(color.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .frame(width: 68, height: 68)
                        .rotationEffect(.degrees(-90))
                    
                    Text("\(Int(pct * 100))%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
            } else {
                ZStack(alignment: .trailing) {
                    Image(systemName: "play.square.stack.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(color.opacity(0.09))
                        .rotationEffect(.degrees(-10))
                        .offset(x: 14, y: 6)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(label ?? "")
                            .font(.system(size: 12, weight: .black))
                            .kerning(1.5)
                            .foregroundStyle(.secondary)
                        
                        Text(value ?? "")
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .foregroundStyle(color)
                        
                        Text(subtitle ?? "")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.8))
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.15 : 0.03), radius: 6, x: 0, y: 3)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(color.opacity(0.12), lineWidth: 0.5)
        }
    }
}

// MARK: - Radar Chart Components

struct RadarChartView: View {
    let data: [(name: String, percentage: Double)]
    let accentColor: Color

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 * 0.62

            ZStack {
                backgroundRings(center: center, radius: radius, count: data.count)
                axisLines(center: center, radius: radius)
                dataShape(center: center, radius: radius)
            }
        }
    }

    @ViewBuilder
    private func backgroundRings(center: CGPoint, radius: CGFloat, count: Int) -> some View {
        ForEach(1...4, id: \.self) { i in
            RadarPolygon(count: count, radius: radius * (Double(i) / 4.0), center: center)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func axisLines(center: CGPoint, radius: CGFloat) -> some View {
        ForEach(0..<data.count, id: \.self) { i in
            RadarAxisLine(
                i: i, count: data.count, name: data[i].name, center: center, radius: radius)
        }
    }

    @ViewBuilder
    private func dataShape(center: CGPoint, radius: CGFloat) -> some View {
        ZStack {
            RadarShape(data: data, center: center, radius: radius, isVisible: true)
                .fill(accentColor.opacity(0.15))

            RadarShape(data: data, center: center, radius: radius, isVisible: true)
                .stroke(accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            
            ForEach(0..<data.count, id: \.self) { i in
                let angle = (Double(i) / Double(data.count)) * 2 * .pi - .pi / 2
                let val = data[i].percentage
                let point = CGPoint(
                    x: center.x + CGFloat(cos(angle)) * radius * CGFloat(val),
                    y: center.y + CGFloat(sin(angle)) * radius * CGFloat(val)
                )
                
                Circle()
                    .fill(accentColor)
                    .frame(width: 7, height: 7)
                    .overlay {
                        Circle()
                            .stroke(Color.white, lineWidth: 1.5)
                    }
                    .shadow(color: accentColor.opacity(0.8), radius: 4)
                    .position(point)
            }
        }
    }
}

private struct RadarAxisLine: View {
    let i: Int
    let count: Int
    let name: String
    let center: CGPoint
    let radius: CGFloat

    var body: some View {
        let angle = (Double(i) / Double(count)) * 2 * .pi - .pi / 2

        Path { path in
            path.move(to: center)
            path.addLine(
                to: CGPoint(
                    x: center.x + CGFloat(cos(angle)) * radius,
                    y: center.y + CGFloat(sin(angle)) * radius
                ))
        }
        .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        let labelPos = CGPoint(
            x: center.x + CGFloat(cos(angle)) * (radius + 22),
            y: center.y + CGFloat(sin(angle)) * (radius + 12)
        )
        Text(name.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .position(labelPos)
    }
}

struct RadarPolygon: Shape {
    let count: Int
    let radius: CGFloat
    let center: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard count >= 3 else { return path }
        for i in 0..<count {
            let angle = (Double(i) / Double(count)) * 2 * .pi - .pi / 2
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

private struct RadarShape: Shape {
    let data: [(name: String, percentage: Double)]
    let center: CGPoint
    let radius: CGFloat
    let isVisible: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0..<data.count {
            let angle = (Double(i) / Double(data.count)) * 2 * .pi - .pi / 2
            let val = isVisible ? data[i].percentage : 0
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius * CGFloat(val),
                y: center.y + CGFloat(sin(angle)) * radius * CGFloat(val)
            )
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

private struct TasteSegment: Identifiable, Sendable {
    let id: UUID
    let label: String
    let count: Int
    let color: Color
    
    init(id: UUID = UUID(), label: String, count: Int, color: Color) {
        self.id = id
        self.label = label
        self.count = count
        self.color = color
    }
}

private struct PulsatingDot: View {
    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 6, height: 6)
    }
}

private struct PulsatingChartNode: View {
    let color: Color
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .overlay {
                Circle()
                    .stroke(Color.white, lineWidth: 1.5)
            }
            .shadow(color: color, radius: 3)
    }
}
