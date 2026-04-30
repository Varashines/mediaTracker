import SwiftUI
import SwiftData

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    
    @State private var stats: LibraryStats?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 100) {
                if isLoading {
                    loadingView
                } else if let stats = stats {
                    // 1. CINEMA DNA: Radar Hero
                    cinemaDNASection(stats: stats)
                    
                    // 2. THE HALL OF FAME: Visual Rankings
                    hallOfFameSection(stats: stats)
                    
                    // 3. THE PRODUCTION DECK: Horizontal Quality Rows
                    productionDeckSection(stats: stats)
                    
                    // 4. CORE MASTERY: Surgical Metrics
                    masterySection(stats: stats)
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 100)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollClipDisabled()
        .onAppear {
            refreshData()
        }
    }

    private func refreshData() {
        Task {
            let actor = LibraryStatsActor(modelContainer: modelContext.container)
            let result = await actor.fetchStats()
            await MainActor.run {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                    self.stats = result
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Sections
    
    @ViewBuilder
    private func cinemaDNASection(stats: LibraryStats) -> some View {
        VStack(alignment: .leading, spacing: 40) {
            VStack(alignment: .leading, spacing: 16) {
                Text("CINEMA DNA")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(appAccent.color)
                    .kerning(5)
                
                Text("Your Cinematic Profile")
                    .font(.system(size: 56, weight: .black, design: .rounded))
            }
            
            HStack(spacing: 80) {
                RadarChartView(data: stats.genreDNA, accentColor: appAccent.color)
                    .frame(width: 450, height: 450)
                
                VStack(alignment: .leading, spacing: 40) {
                    let topGenre = stats.topRatedGenres.first?.0 ?? "Cinema"
                    let topActor = stats.topRatedActors.first?.name ?? "Great Talent"
                    
                    Text("An expert in ") + 
                    Text(topGenre).foregroundColor(appAccent.color) +
                    Text(", driven by the performances of ") +
                    Text(topActor).foregroundColor(appAccent.color) +
                    Text(".")
                    
                    VStack(alignment: .leading, spacing: 20) {
                        metricSimple(label: "TOTAL WATCH TIME", value: formatWatchTimeSimple(minutes: stats.totalWatchTimeMinutes))
                        metricSimple(label: "COLLECTION SIZE", value: "\(stats.totalMovies + stats.totalTVShows) TITLES")
                    }
                }
                .font(.system(size: 32, weight: .black, design: .rounded))
                .lineSpacing(6)
            }
        }
    }

    @ViewBuilder
    private func hallOfFameSection(stats: LibraryStats) -> some View {
        VStack(alignment: .leading, spacing: 80) {
            hallOfFameRow(title: "ACTORS HALL OF FAME", people: stats.topRatedActors, color: .orange)
            hallOfFameRow(title: "CREATORS HALL OF FAME", people: stats.topRatedCreators, color: .green)
        }
    }

    @ViewBuilder
    private func productionDeckSection(stats: LibraryStats) -> some View {
        VStack(alignment: .leading, spacing: 60) {
            headerMini("PRODUCTION DECK")
            
            VStack(alignment: .leading, spacing: 50) {
                horizontalAffinityList(title: "Studios", data: stats.topRatedNetworks, icon: "tv.fill", color: .purple)
                horizontalAffinityList(title: "Languages", data: stats.topRatedLanguages, icon: "globe", color: .mint)
                horizontalAffinityList(title: "Highest Rated Genres", data: stats.topRatedGenres, icon: "tag.fill", color: .blue)
            }
        }
    }

    @ViewBuilder
    private func masterySection(stats: LibraryStats) -> some View {
        VStack(alignment: .leading, spacing: 40) {
            headerMini("MASTERED COLLECTIONS")
            
            HStack(spacing: 30) {
                masteryCard(title: "Movies", current: stats.completedMovies, total: stats.totalMovies, color: .blue)
                masteryCard(title: "TV Shows", current: stats.completedTVShows, total: stats.totalTVShows, color: .purple)
                masteryCard(label: "EPISODES", value: "\(stats.totalEpisodesWatched)", subtitle: "WATCHED", color: .orange)
            }
        }
    }

    // MARK: - Components
    
    @ViewBuilder
    private func horizontalAffinityList(title: String, data: [(String, Double)], icon: String, color: Color) -> some View {
        if !data.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: icon).foregroundStyle(color).font(.system(size: 16, weight: .bold))
                    Text(title.uppercased()).font(.system(size: 13, weight: .black)).kerning(2)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(data, id: \.0) { item in
                            affinityCard(name: item.0, score: item.1, color: color)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    @ViewBuilder
    private func affinityCard(name: String, score: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .lineLimit(1)
            
            HStack(spacing: 6) {
                Text("\(Int(score * 100))")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(color)
                Text("SCORE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(minWidth: 160, alignment: .leading)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func hallOfFameRow(title: String, people: [VisualPersonStat], color: Color) -> some View {
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 30) {
                headerMini(title)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 24) {
                        ForEach(people, id: \.name) { person in
                            personCard(person: person, accentColor: color)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    @ViewBuilder
    private func personCard(person: VisualPersonStat, accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                if let urlString = person.profileURL, let url = URL(string: urlString) {
                    CachedImage(url: url, targetSize: CGSize(width: 200, height: 300)) { _ in }
                        placeholder: { Color.secondary.opacity(0.1) }
                } else {
                    Color.secondary.opacity(0.1)
                        .overlay { Image(systemName: "person.fill").font(.largeTitle).foregroundStyle(.secondary) }
                }
            }
            .frame(width: 160, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(person.name)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .lineLimit(1)
                
                HStack {
                    Text("\(Int(person.score * 100))")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundStyle(accentColor)
                    Text("SCORE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func masteryCard(title: String? = nil, label: String? = nil, value: String? = nil, subtitle: String? = nil, current: Int = 0, total: Int = 0, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let title = title {
                Text(title.uppercased()).font(.system(size: 10, weight: .black)).kerning(2).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(current)").font(.system(size: 42, weight: .black, design: .rounded))
                    Text("/ \(total)").font(.system(size: 18, weight: .bold)).foregroundStyle(.secondary)
                }
                ProgressView(value: total > 0 ? Double(current) / Double(total) : 0)
                    .tint(color)
            } else {
                Text(label ?? "").font(.system(size: 10, weight: .black)).kerning(2).foregroundStyle(.secondary)
                Text(value ?? "").font(.system(size: 42, weight: .black, design: .rounded)).foregroundStyle(color)
                Text(subtitle ?? "").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(minWidth: 200, alignment: .leading)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Helpers
    
    private func headerMini(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .black)).foregroundStyle(.secondary).kerning(4)
    }

    private func metricSimple(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10, weight: .black)).kerning(2).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(appAccent.color)
        }
    }

    private func formatWatchTimeSimple(minutes: Int) -> String {
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        return "\(hours)h \(minutes % 60)m"
    }

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 30) {
            ProgressView().controlSize(.large)
            Text("EXTRACTING CINEMA DNA").font(.system(size: 12, weight: .black)).kerning(2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 600)
    }
}

// MARK: - Radar Chart Component
struct RadarChartView: View {
    let data: [(name: String, percentage: Double)]
    let accentColor: Color
    
    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 * 0.7
            
            ZStack {
                // Background Rings
                ForEach(1...4, id: \.self) { i in
                    Circle()
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                        .frame(width: radius * 2 * (Double(i) / 4), height: radius * 2 * (Double(i) / 4))
                }
                
                // Axis lines
                ForEach(0..<data.count, id: \.self) { i in
                    let angle = (Double(i) / Double(data.count)) * 2 * .pi - .pi / 2
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: CGPoint(
                            x: center.x + CGFloat(cos(angle)) * radius,
                            y: center.y + CGFloat(sin(angle)) * radius
                        ))
                    }
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    
                    // Labels
                    let labelPos = CGPoint(
                        x: center.x + CGFloat(cos(angle)) * (radius + 40),
                        y: center.y + CGFloat(sin(angle)) * (radius + 20)
                    )
                    Text(data[i].name.uppercased())
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.secondary)
                        .position(labelPos)
                }
                
                // Data Shape
                Path { path in
                    for i in 0..<data.count {
                        let angle = (Double(i) / Double(data.count)) * 2 * .pi - .pi / 2
                        let val = data[i].percentage // Use affinity score directly (0-1)
                        let point = CGPoint(
                            x: center.x + CGFloat(cos(angle)) * radius * CGFloat(val),
                            y: center.y + CGFloat(sin(angle)) * radius * CGFloat(val)
                        )
                        if i == 0 { path.move(to: point) }
                        else { path.addLine(to: point) }
                    }
                    path.closeSubpath()
                }
                .fill(accentColor.opacity(0.2))
                
                Path { path in
                    for i in 0..<data.count {
                        let angle = (Double(i) / Double(data.count)) * 2 * .pi - .pi / 2
                        let val = data[i].percentage
                        let point = CGPoint(
                            x: center.x + CGFloat(cos(angle)) * radius * CGFloat(val),
                            y: center.y + CGFloat(sin(angle)) * radius * CGFloat(val)
                        )
                        if i == 0 { path.move(to: point) }
                        else { path.addLine(to: point) }
                    }
                    path.closeSubpath()
                }
                .stroke(accentColor, lineWidth: 3)
            }
        }
    }
}
