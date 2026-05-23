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

    @Query(sort: \MediaItem.lastInteractionDate, order: .reverse) private var allItems: [MediaItem]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()
            
            // Atmospheric gradient glow
            GeometryReader { geo in
                RadialGradient(
                    colors: [Color.accentColor.opacity(colorScheme == .dark ? 0.12 : 0.04), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: min(geo.size.width, geo.size.height) * 0.9
                )
                .ignoresSafeArea()
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if isLoading {
                        loadingView
                    } else if let stats = stats {
                        // Empty space to push content below native title bar
                        Spacer()
                            .frame(height: 12)
                        
                        // Cinephile Barcode Header (Unique Library Fingerprint)
                        CinephileBarcodeView(items: allItems)
                        
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
        // Hero Statistics Grid (Passport/Calibration merged & flattened)
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 32) {
                metricField(label: "TOTAL LIBRARY", value: "\(stats.totalMovies + stats.totalTVShows)", subValue: "\(stats.totalMovies) Movies • \(stats.totalTVShows) TV Shows")
                dividerLine
                metricField(label: "WATCH VOLUME", value: formatWatchTimeSimple(minutes: stats.totalWatchTimeMinutes), subValue: "\(stats.totalEpisodesWatched) Episodes Watched")
                dividerLine
                metricField(label: "TASTE DISTRIBUTION", value: "\(stats.lovedCount) / \(stats.likedCount) / \(stats.dislikedCount)", subValue: "Love / Like / Dislike Ratio")
                dividerLine
                metricField(label: "LIBRARY ARCHETYPE", value: calculateArchetype(stats: stats).title.uppercased(), subValue: calculateArchetype(stats: stats).description)
            }
            .padding(.vertical, 16)
            
            Divider()
                .opacity(0.12)
        }
        
        // High-Density Affinity Ledger Tables (Genres, Studios, Networks, Languages)
        affinityLedgerSection(stats: stats)
        
        // Decade Distribution Chart
        decadeDistributionSection(stats: stats)
    }

    @ViewBuilder
    private func activityTabContent(stats: LibraryStats) -> some View {
        // High-Density Top Talent list (split layout)
        TalentLedgerView(stats: stats)
        
        // Top actor-director collaborations
        CollaborationsLedgerView(collaborations: stats.collaborations)
        
        // Watch Log Timeline (git-style history log)
        WatchLogTimelineView(completedItems: stats.completedItems)
        
        // Mastery Section
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
    private func premiumCard<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        PremiumCard(content: content)
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

    private var dividerLine: some View {
        Divider()
            .frame(width: 1)
            .frame(height: 48)
            .opacity(0.12)
    }

    @ViewBuilder
    private func metricField(label: String, value: String, subValue: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.secondary)
                .kerning(1.5)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(subValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: 180, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func affinityLedgerSection(stats: LibraryStats) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionLabel("AFFINITY LEDGER", icon: "tablecells")
            
            HStack(alignment: .top, spacing: 32) {
                // Column 1: Top Genres
                VStack(alignment: .leading, spacing: 12) {
                    tableHeader(title: "GENRES")
                    ForEach(stats.genreDNA.prefix(5), id: \.name) { item in
                        tableRow(name: item.name, value: String(format: "%.0f%%", item.percentage * 100))
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Column 2: Top Studios & Networks
                VStack(alignment: .leading, spacing: 12) {
                    tableHeader(title: "STUDIOS & NETWORKS")
                    let topStudios = stats.topRatedStudios.prefix(3).map { (name: $0.name, type: "Studio", score: $0.score) }
                    let topNetworks = stats.topRatedNetworks.prefix(2).map { (name: $0.name, type: "Network", score: $0.score) }
                    let combined = (topStudios + topNetworks).sorted { $0.score > $1.score }
                    ForEach(combined, id: \.name) { item in
                        tableRow(name: item.name, value: String(format: "%.1f ★", item.score))
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Column 3: Languages
                VStack(alignment: .leading, spacing: 12) {
                    tableHeader(title: "LANGUAGES")
                    ForEach(stats.topRatedLanguages.prefix(5), id: \.name) { item in
                        tableRow(name: item.name.uppercased(), value: String(format: "%.1f ★", item.score))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
            
            Divider()
                .opacity(0.12)
        }
    }

    @ViewBuilder
    private func tableHeader(title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .kerning(1.5)
                .foregroundStyle(.secondary)
            Divider()
                .opacity(0.12)
        }
    }
    
    @ViewBuilder
    private func tableRow(name: String, value: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.vertical, 6)
            
            Divider()
                .opacity(0.06)
        }
    }

    @ViewBuilder
    private func decadeDistributionSection(stats: LibraryStats) -> some View {
        if !stats.decadeDistribution.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                sectionLabel("DECADE DISTRIBUTION", icon: "calendar")
                
                VStack(spacing: 8) {
                    let maxCount = stats.decadeDistribution.map { $0.count }.max() ?? 1
                    ForEach(stats.decadeDistribution) { point in
                        HStack(spacing: 12) {
                            Text(point.decade)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .leading)
                            
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor.opacity(0.15))
                                    .overlay(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.accentColor)
                                            .frame(width: geo.size.width * CGFloat(Double(point.count) / Double(maxCount)))
                                    }
                            }
                            .frame(height: 8)
                            
                            Text("\(point.count) titles")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.primary)
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                }
                .padding(.vertical, 8)
                
                Divider()
                    .opacity(0.12)
            }
        }
    }

    @ViewBuilder
    private func masterySection(stats: LibraryStats) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("LIBRARY COMPLETION & MASTERY", icon: "checkmark.seal.fill")

            HStack(spacing: 32) {
                masteryRow(title: "MOVIES COMPLETION", current: stats.completedMovies, total: stats.totalMovies, color: .blue)
                dividerLine
                masteryRow(title: "TV SHOWS COMPLETION", current: stats.completedTVShows, total: stats.totalTVShows, color: .purple)
                dividerLine
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOTAL EPISODES WATCHED")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.secondary)
                        .kerning(1.5)
                    Text("\(stats.totalEpisodesWatched)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                    Text("Record count in database")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
        }
    }
    
    @ViewBuilder
    private func masteryRow(title: String, current: Int, total: Int, color: Color) -> some View {
        let pct = total > 0 ? Double(current) / Double(total) : 0.0
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.secondary)
                .kerning(1.5)
            
            HStack(spacing: 8) {
                Text("\(current) / \(total)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text(String(format: "(%.0f%%)", pct * 100))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }
            
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.12))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(pct))
                    }
            }
            .frame(height: 4)
            .frame(maxWidth: 160)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Shared File-Scoped Helpers

@ViewBuilder
func sectionLabel(_ text: String, icon: String) -> some View {
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

// MARK: - Cinephile Barcode Component

struct CinephileBarcodeView: View {
    let items: [MediaItem]
    @State private var hoveredItem: MediaItem?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CINEMA DNA SIGNATURE")
                    .font(.system(size: 10, weight: .black))
                    .kerning(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
                if let item = hoveredItem {
                    HStack(spacing: 6) {
                        Text(item.title.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(item.tasteValue == "None" ? "UNRATED" : item.tasteValue.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(item.tasteValue == "Love" ? .red : item.tasteValue == "Like" ? .blue : item.tasteValue == "Dislike" ? .orange : .secondary)
                    }
                    .transition(.opacity)
                } else {
                    Text("DECODING CONSOLE: HOVER TO SCAN")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.4))
                }
            }
            
            // Barcode Strip
            let validItems = items.filter { $0.themeColorHex != nil }
            if validItems.isEmpty {
                HStack {
                    Spacer()
                    Text("Add rated or themed titles to generate signature")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(height: 24)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(validItems) { item in
                            let isCurrentHovered = hoveredItem?.id == item.id
                            
                            RoundedRectangle(cornerRadius: 0)
                                .fill(Color.primary.opacity(isCurrentHovered ? 1.0 : (item.tasteValue == "Love" ? 0.8 : item.tasteValue == "Like" ? 0.5 : item.tasteValue == "Dislike" ? 0.25 : 0.12)))
                                .frame(width: 3)
                                .frame(height: 24)
                                .scaleEffect(y: isCurrentHovered ? 1.25 : 1.0)
                                .onHover { isHovered in
                                    withAnimation(.spring(response: 0.15, dampingFraction: 0.75)) {
                                        if isHovered {
                                            hoveredItem = item
                                        } else if hoveredItem?.id == item.id {
                                            hoveredItem = nil
                                        }
                                    }
                                }
                        }
                    }
                    .frame(height: 32)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            
            Divider()
                .opacity(0.12)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Talent Ledger Component

struct TalentLedgerView: View {
    let stats: LibraryStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionLabel("TOP RATED TALENT", icon: "person.3.fill")
            
            HStack(alignment: .top, spacing: 32) {
                // Column 1: Top Actors
                talentColumn(title: "TOP ACTORS", people: stats.topRatedActors, color: .orange)
                    .frame(maxWidth: .infinity)
                
                // Column 2: Top Directors & Creators
                talentColumn(title: "TOP DIRECTORS & CREATORS", people: stats.topRatedCreators, color: .green)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
            
            Divider()
                .opacity(0.12)
        }
    }
    
    @ViewBuilder
    private func talentColumn(title: String, people: [VisualPersonStat], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1.5)
                    .foregroundStyle(.secondary)
                Divider()
                    .opacity(0.12)
            }
            
            if people.isEmpty {
                Text("No talent records in this category")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(Array(people.prefix(5).enumerated()), id: \.element.name) { index, person in
                    let rank = index + 1
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Text("#\(rank)")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundStyle(color)
                                .frame(width: 20, alignment: .leading)
                            
                            // Minimal avatar
                            ZStack {
                                Circle()
                                    .fill(color.opacity(0.1))
                                    .frame(width: 24, height: 24)
                                
                                if let urlStr = person.profileURL, let url = URL(string: urlStr) {
                                    CachedImage(url: url, targetSize: CGSize(width: 48, height: 48), priority: .normal) {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(color.opacity(0.5))
                                    }
                                    .frame(width: 24, height: 24)
                                    .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(color)
                                }
                            }
                            
                            Text(person.name)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text("\(person.count) titles")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            
                            Text(String(format: "%.0f%%", person.score * 100))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(color)
                                .frame(width: 35, alignment: .trailing)
                        }
                        .padding(.vertical, 6)
                        
                        Divider()
                            .opacity(0.06)
                    }
                }
            }
        }
    }
}

// MARK: - Collaborations Ledger Component

struct CollaborationsLedgerView: View {
    let collaborations: [CreatorCollaboration]
    
    var body: some View {
        if !collaborations.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                sectionLabel("CREATIVE COLLABORATIONS", icon: "link")
                
                VStack(alignment: .leading, spacing: 0) {
                    // Header row
                    HStack {
                        Text("ACTOR")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text("DIRECTOR / CREATOR")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text("COLLABORATIONS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .trailing)
                    }
                    .padding(.bottom, 6)
                    
                    Divider()
                        .opacity(0.12)
                    
                    ForEach(collaborations.prefix(5)) { col in
                        VStack(spacing: 0) {
                            HStack {
                                Text(col.actorName)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Text(col.creatorName)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Text("\(col.count) titles")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 120, alignment: .trailing)
                            }
                            .padding(.vertical, 8)
                            
                            Divider()
                                .opacity(0.06)
                        }
                    }
                }
                .padding(.vertical, 8)
                
                Divider()
                    .opacity(0.12)
            }
        }
    }
}

// MARK: - Watch Log Timeline Component

struct WatchLogTimelineView: View {
    let completedItems: [CompletedItemRepresentation]
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("CHRONOLOGICAL WATCH LOG", icon: "clock.arrow.circlepath")
            
            if completedItems.isEmpty {
                Text("No watch history records")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(completedItems.prefix(15).enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .top, spacing: 16) {
                            // Timeline dot & line
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 4)
                                
                                if index < completedItems.prefix(15).count - 1 {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.12))
                                        .frame(width: 1)
                                        .frame(maxHeight: .infinity)
                                }
                            }
                            .frame(width: 12)
                            
                            // Date
                            Text(formatDate(item.completedDate))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .leading)
                                .padding(.top, 1)
                            
                            // Title & Type capsule
                            HStack(spacing: 8) {
                                if let urlStr = item.posterURL, let url = URL(string: urlStr) {
                                    CachedImage(url: url, targetSize: CGSize(width: 40, height: 60), priority: .normal) {
                                        Color.secondary.opacity(0.1)
                                    }
                                    .frame(width: 20, height: 30)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    
                                    HStack(spacing: 6) {
                                        Text(item.typeValue.uppercased())
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.primary.opacity(0.06))
                                            .clipShape(RoundedRectangle(cornerRadius: 2))
                                    }
                                }
                            }
                            
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                }
                .padding(.vertical, 8)
            }
            
            Divider()
                .opacity(0.12)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, yyyy"
        return formatter.string(from: date).uppercased()
    }
}

// MARK: - Premium Card Container

struct PremiumCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: () -> Content
    
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    var body: some View {
        content()
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.thinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.15 : 0.02), radius: 10, x: 0, y: 4)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.05), lineWidth: 0.5)
            }
    }
}
