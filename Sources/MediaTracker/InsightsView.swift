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
                    // 1. Surgical Hero: The Taste Identity
                    tasteIdentityHero(stats: stats)
                    
                    // 2. Core Metrics: Performance & Feeling
                    HStack(alignment: .top, spacing: 40) {
                        watchTimeCard(minutes: stats.totalWatchTimeMinutes)
                        tasteScoreCard(stats: stats)
                        completionCard(stats: stats)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // 3. The Affinity Map: Quality Rankings
                    VStack(alignment: .leading, spacing: 60) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("AFFINITY MAP")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(appAccent.color)
                                .kerning(4)
                            Text("Your highest rated categories based on consistent love and engagement.")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 40), 
                            GridItem(.flexible(), spacing: 40),
                            GridItem(.flexible(), spacing: 40)
                        ], spacing: 60) {
                            affinityGroup(title: "Genres", data: stats.topRatedGenres, icon: "tag.fill", color: .blue)
                            affinityGroup(title: "Studios", data: stats.topRatedNetworks, icon: "tv.fill", color: .purple)
                            affinityGroup(title: "Actors", data: stats.topRatedActors, icon: "person.2.fill", color: .orange)
                            affinityGroup(title: "Creators", data: stats.topRatedCreators, icon: "briefcase.fill", color: .green)
                            affinityGroup(title: "Languages", data: stats.topRatedLanguages, icon: "globe", color: .mint)
                        }
                    }
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

    // MARK: - Hero
    
    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 30) {
            ProgressView().controlSize(.large)
            Text("CALIBRATING INSIGHTS")
                .font(.system(size: 12, weight: .black)).kerning(2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 600)
    }

    @ViewBuilder
    private func tasteIdentityHero(stats: LibraryStats) -> some View {
        let topGenre = stats.topRatedGenres.first?.0 ?? "Cinema"
        let topActor = stats.topRatedActors.first?.0 ?? "Great Talent"
        
        VStack(alignment: .leading, spacing: 24) {
            Text("TASTE PROFILE")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(appAccent.color)
                .kerning(5)
            
            Text("An expert in ") + 
            Text(topGenre).foregroundColor(appAccent.color) +
            Text(", driven by the performances of ") +
            Text(topActor).foregroundColor(appAccent.color) +
            Text(".")
        }
        .font(.system(size: 56, weight: .black, design: .rounded))
        .lineSpacing(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Core Cards
    
    @ViewBuilder
    private func watchTimeCard(minutes: Int) -> some View {
        let (days, hours, _) = formatWatchTime(minutes: minutes)
        
        VStack(alignment: .leading, spacing: 16) {
            headerMini("LIFETIME")
            
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if days > 0 {
                    Text("\(days)").font(.system(size: 48, weight: .black, design: .rounded))
                    Text("DAYS").font(.system(size: 12, weight: .black)).foregroundStyle(.secondary)
                }
                Text("\(hours)").font(.system(size: 48, weight: .black, design: .rounded))
                Text("HRS").font(.system(size: 12, weight: .black)).foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func tasteScoreCard(stats: LibraryStats) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            headerMini("SENTIMENT")
            
            HStack(spacing: 24) {
                sentimentMini(label: "LOVED", value: stats.lovedCount, color: .red)
                sentimentMini(label: "LIKED", value: stats.likedCount, color: .blue)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func completionCard(stats: LibraryStats) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            headerMini("MASTERY")
            
            HStack(spacing: 30) {
                miniRing(current: stats.completedMovies, total: stats.totalMovies, label: "MOVIES", color: .blue)
                miniRing(current: stats.completedTVShows, total: stats.totalTVShows, label: "TV", color: .purple)
            }
        }
        .cardStyle()
    }

    // MARK: - Affinity Section
    
    @ViewBuilder
    private func affinityGroup(title: String, data: [(String, Double)], icon: String, color: Color) -> some View {
        if !data.isEmpty {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Image(systemName: icon).foregroundStyle(color).font(.system(size: 18, weight: .bold))
                    Text(title.uppercased()).font(.system(size: 14, weight: .black)).kerning(2)
                }
                
                VStack(spacing: 12) {
                    ForEach(data, id: \.0) { item in
                        affinityRow(name: item.0, score: item.1, color: color)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func affinityRow(name: String, score: Double, color: Color) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
            
            Spacer()
            
            // Score Bar: Simple, Profesh
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.1)).frame(width: 60, height: 6)
                Capsule().fill(color).frame(width: 60 * score, height: 6)
            }
            
            Text(String(format: "%.0f", score * 100))
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Surgical Helpers
    
    private func headerMini(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .black))
            .foregroundStyle(.secondary)
            .kerning(3)
    }

    private func sentimentMini(label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)").font(.system(size: 32, weight: .black, design: .rounded))
            Text(label).font(.system(size: 9, weight: .black)).foregroundStyle(color).kerning(1)
        }
    }

    private func miniRing(current: Int, total: Int, label: String, color: Color) -> some View {
        let percentage = total > 0 ? Double(current) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 4) {
            ZStack {
                Circle().stroke(color.opacity(0.1), lineWidth: 4)
                Circle().trim(from: 0, to: percentage).stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
            }
            .frame(width: 32, height: 32)
            Text(label).font(.system(size: 8, weight: .black)).foregroundStyle(.secondary)
        }
    }

    private func formatWatchTime(minutes: Int) -> (days: Int, hours: Int, mins: Int) {
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let mins = minutes % 60
        return (days, hours, mins)
    }
}

// MARK: - Modifiers
extension View {
    func cardStyle() -> some View {
        self.padding(32)
            .background(Color.secondary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
    }
}
