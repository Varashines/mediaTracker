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
                        // Section 0: Passport Header
                        PassportHeaderView(stats: stats)

                        // Section 1: Hero Stats + Taste DNA
                        HStack(alignment: .top, spacing: AppTheme.Spacing.large) {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                                SectionHeader(title: "Overview", icon: "chart.bar.fill", iconColor: .pink)
                                HeroStatPills(stats: stats)
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                                SectionHeader(title: "Taste DNA", icon: "heart.circle.fill", iconColor: .pink)
                                TasteDNAView(stats: stats)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)

                        // Section 3: Genre Constellation
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                            SectionHeader(title: "Genre Constellation", icon: "sparkles", iconColor: .indigo)
                            GenreConstellationView(items: Array(stats.genreDNA.prefix(6)))
                        }

                        // Section 4: Spectrum
                        SpectrumView(items: stats.barcodeData)

                        // Section 7: Studios, Networks & Languages
                        StudiosNetworksView(stats: stats, modelContext: modelContext)

                        // Section 8: Hall of Fame
                        HallOfFameView(stats: stats)
                    }
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.always)
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
