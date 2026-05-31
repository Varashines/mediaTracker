import SwiftData
import SwiftUI

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme

    @State private var stats: LibraryStats?
    @State private var isLoading = true
    @State private var statsTask: Task<Void, Never>? = nil
    var refreshID: Int = 0
    
    @AppStorage("theme_preference") private var themePreference = 0
    @AppStorage("custom_theme_palette") private var customThemePalette = 0

    var body: some View {
        ZStack {
            Color.clear
                .adaptiveBackground()
                .ignoresSafeArea()

            if isLoading {
                InsightsSkeletonView()
            } else if let stats = stats {
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.section) {
                        // Title with Link to Cinephile Lab
                        HStack {
                            Text("Insights")
                                .font(AppTheme.Font.title)
                            
                            Spacer()
                            
                            NavigationLink(value: CinephileLabDestination()) {
                                HStack(spacing: 6) {
                                    Image(systemName: "chart.bar.doc.horizontal.fill")
                                    Text("Cinephile Lab")
                                }
                                .font(AppTheme.Font.bodyBold)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(0.12))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
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
                    }
                    .padding(.bottom, AppTheme.Spacing.section)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .navigationDestination(for: CinephileLabDestination.self) { _ in
                    CinephileLabView()
                }
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
        let container = modelContext.container
        statsTask?.cancel()
        statsTask = Task {
            await performFetch(container: container)
        }
    }

    private func performFetch(container: ModelContainer) async {
        let actor = LibraryStatsActor(modelContainer: container)
        do {
            let result = try await actor.fetchStats(includeCinephileData: false)
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
            .background(AppTheme.Colors.cardFill(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), lineWidth: 0.5)
            )
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
                    .font(AppTheme.Font.monoSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .frame(width: 240, height: 86, alignment: .leading)
        .background(
            ClaymorphicCard(color: color, isHovered: isHovered)
        )
        .scaleEffect(isHovered ? 1.04 : 1.0)
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

    var body: some View {
        let completionRate: Double = {
            let total = stats.totalMovies + stats.totalTVShows
            guard total > 0 else { return 0 }
            return Double(stats.completedMovies + stats.completedTVShows) / Double(total)
        }()
        let overallAffinity: Double = {
            let totalRated = stats.lovedCount + stats.likedCount + stats.dislikedCount
            guard totalRated > 0 else { return 0 }
            let score = (3.0 * Double(stats.lovedCount) + 1.0 * Double(stats.likedCount) - 2.0 * Double(stats.dislikedCount)) / (3.0 * Double(totalRated))
            return max(0, score)
        }()
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
                        .font(AppTheme.Font.title3)
                        .foregroundStyle(color)
                    Text("Affinity")
                        .font(AppTheme.Font.smallBold)
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

// MARK: - Skeletons




