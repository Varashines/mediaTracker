import SwiftData
import SwiftUI

private let insightsScrollName = "insightsScroll"

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme

    @State private var stats: LibraryStats?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var statsTask: Task<Void, Never>?
    @State private var scrollOffset: CGFloat = 0
    @Namespace private var flipNamespace
    var refreshID: Int = 0

    private var backgroundTint: Color {
        let progress = max(0, min(1, -scrollOffset / 800))
        let colors: [Color] = [
            AppTheme.Colors.accent,
            .pink,
            .indigo,
            .orange,
            .purple
        ]
        let segment = progress * CGFloat(colors.count - 1)
        let idx = Int(segment)
        let frac = segment - CGFloat(idx)
        guard idx + 1 < colors.count else {
            return (colors.last ?? AppTheme.Colors.accent).opacity(0.05)
        }
        return colors[idx].opacity(0.06 - Double(frac) * 0.01)
    }

    var body: some View {
        ZStack {
            AppTheme.Colors.background(for: colorScheme)
                .overlay(backgroundTint)
                .ignoresSafeArea()

            if isLoading {
                InsightsSkeletonView()
            } else if let stats = stats {
                ScrollView {
                    LazyVStack(spacing: AppTheme.Spacing.section) {
                        PassportHeaderView(stats: stats)

                        SectionDivider(color: AppTheme.Colors.accent)

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

                        SectionDivider(color: .pink)

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                            SectionHeader(title: "Genre Constellation", icon: "sparkles", iconColor: .indigo)
                            GenreConstellationView(items: Array(stats.genreDNA.prefix(8)))
                        }

                        SectionDivider(color: .indigo)

                        StudiosNetworksView(stats: stats, modelContext: modelContext)

                        SectionDivider(color: .orange)

                        HallOfFameView(stats: stats)
                    }
                    .padding(.vertical, AppTheme.Spacing.xLarge)
                    .frame(maxWidth: .infinity)
                    .background(alignment: .top) {
                        GeometryReader { geo in
                            let offset = geo.frame(in: .named(insightsScrollName)).minY
                            Color.clear
                                .preference(key: ScrollOffsetKey.self, value: [insightsScrollName: offset])
                        }
                    }
                }
                .coordinateSpace(name: insightsScrollName)
                .scrollBounceBehavior(.always)
                .onPreferenceChange(ScrollOffsetKey.self) { offsets in
                    scrollOffset = offsets[insightsScrollName] ?? 0
                }
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Could not load insights")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") { refreshData() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    withAnimation(AppTheme.Animation.easeInOut) {
                        self.stats = result
                        self.isLoading = false
                    }
                }
            } catch {
                if !(error is CancellationError) {
                    AppLogger.debug("Error fetching stats: \(error)")
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                    }
                }
            }
        }
    }
}

// MARK: - Flip Card with Solari Strip Lines

private struct FlipCard<Front: View, Back: View>: View {
    let front: Front
    let back: Back
    let isFlipped: Bool
    var stripCount: Int = 8

    var body: some View {
        ZStack {
            // Front side
            if !isFlipped {
                front
            }

            // Back side (counter-rotated so text stays readable)
            if isFlipped {
                back
                    .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
            }
        }
        .frame(maxWidth: .infinity)
        .rotation3DEffect(
            .degrees(isFlipped ? 180 : 0),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.5
        )
        .overlay(alignment: .center) {
            // Decorative strip lines — animate in during flip
            if abs(angle) > 10 && abs(angle) < 170 {
                VStack(spacing: 0) {
                    ForEach(0..<stripCount - 1, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.primary.opacity(0.1))
                            .frame(height: 1)
                        Spacer()
                    }
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
    }

    private var angle: Double {
        isFlipped ? 180 : 0
    }
}
