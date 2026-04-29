import SwiftUI
import SwiftData

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    
    @State private var stats: LibraryStats?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 50) {
                if isLoading {
                    loadingView
                } else if let stats = stats {
                    // 1. Hero: Total Watch Time
                    watchTimeHero(minutes: stats.totalWatchTimeMinutes)
                    
                    // 2. Overview Grid
                    metricsGrid(stats: stats)
                    
                    // 3. Genres & Networks
                    HStack(alignment: .top, spacing: 40) {
                        distributionSection(title: "Top Genres", data: stats.topGenres, icon: "tag.fill")
                        distributionSection(title: "Top Networks", data: stats.topNetworks, icon: "tv.fill")
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 40)
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
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    self.stats = result
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Components
    
    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("Analyzing your collection...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    @ViewBuilder
    private func watchTimeHero(minutes: Int) -> some View {
        let (days, hours, mins) = formatWatchTime(minutes: minutes)
        
        VStack(alignment: .leading, spacing: 16) {
            Text("TOTAL WATCH TIME")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(appAccent.color)
                .kerning(2)
            
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if days > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(days)").font(.system(size: 64, weight: .black, design: .rounded))
                        Text("days").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(hours)").font(.system(size: 64, weight: .black, design: .rounded))
                    Text("hrs").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(mins)").font(.system(size: 64, weight: .black, design: .rounded))
                    Text("mins").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appAccent.color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .overlay(
            RoundedRectangle(cornerRadius: 32)
                .stroke(appAccent.color.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func metricsGrid(stats: LibraryStats) -> some View {
        let movieRate = stats.totalMovies > 0 ? Int((Double(stats.completedMovies) / Double(stats.totalMovies)) * 100) : 0
        let tvRate = stats.totalTVShows > 0 ? Int((Double(stats.completedTVShows) / Double(stats.totalTVShows)) * 100) : 0
        
        VStack(alignment: .leading, spacing: 25) {
            Text("Library Overview")
                .font(.system(size: 24, weight: .black, design: .rounded))
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                metricCard(label: "Movies", value: "\(stats.totalMovies)", subValue: "\(movieRate)% Finished", icon: "film.fill", color: .blue)
                metricCard(label: "TV Shows", value: "\(stats.totalTVShows)", subValue: "\(tvRate)% Finished", icon: "tv.fill", color: .purple)
                metricCard(label: "Episodes", value: "\(stats.totalEpisodesWatched)", subValue: "Watched", icon: "play.rectangle.fill", color: .orange)
                metricCard(label: "Library Size", value: "\(stats.totalMovies + stats.totalTVShows)", subValue: "Titles", icon: "tray.full.fill", color: .green)
            }
        }
    }

    @ViewBuilder
    private func metricCard(label: String, value: String, subValue: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                Text(label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            
            Text(subValue)
                .font(.system(size: 11, weight: .black))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.1))
                .foregroundStyle(color)
                .clipShape(Capsule())
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private func distributionSection(title: String, data: [(name: String, count: Int)], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(appAccent.color)
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            
            VStack(spacing: 12) {
                ForEach(data.prefix(8), id: \.name) { entry in
                    HStack {
                        Text(entry.name)
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text("\(entry.count)")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func formatWatchTime(minutes: Int) -> (days: Int, hours: Int, mins: Int) {
        let days = minutes / (24 * 60)
        let hours = (minutes % (24 * 60)) / 60
        let mins = minutes % 60
        return (days, hours, mins)
    }
}
