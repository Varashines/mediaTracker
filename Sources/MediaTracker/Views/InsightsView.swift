import SwiftData
import SwiftUI

private let insightsScrollName = "insightsScroll"

private enum InsightTab: String, CaseIterable {
    case overview = "Overview"
    case browse = "Browse"

    var icon: String {
        switch self {
        case .overview: return "chart.bar.fill"
        case .browse: return "square.grid.2x2.fill"
        }
    }
}

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme

    @State private var stats: LibraryStats?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var statsTask: Task<Void, Never>?
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollOffsetDebounced: CGFloat = 0
    @State private var isFastScrolling = false
    @State private var scrollTask: Task<Void, Never>?
    @State private var backgroundTintTask: Task<Void, Never>?
    @State private var selectedTab: InsightTab = .overview
    @State private var showSpectrum = false
    @State private var showingShareSheet = false
    @State private var shareImage: NSImage? = nil
    @State private var hoveredTab: InsightTab? = nil
    @Namespace private var insightsNamespace
    @Namespace private var flipNamespace
    var refreshID: Int = 0

    private var backgroundTint: Color {
        let progress = max(0, min(1, -scrollOffsetDebounced / 600))
        let intensity = UserDefaults.standard.double(forKey: "background_intensity")
        let scaled = progress * max(0.02, intensity * 0.04)
        let isDark = colorScheme == .dark
        return AppTheme.Colors.accent.opacity(isDark ? scaled : scaled * 0.5)
    }

    var body: some View {
        ZStack {
            AppTheme.Colors.background(for: colorScheme)
                .overlay(backgroundTint)
                .ignoresSafeArea()

            if isLoading {
                InsightsSkeletonView()
            } else if let stats = stats {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Spacer()
                        InsightTabPill(tab: .overview, selectedTab: $selectedTab)
                        InsightTabPill(tab: .browse, selectedTab: $selectedTab)
                        Spacer()
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .padding(.vertical, AppTheme.Spacing.small)

                    ScrollView {
                        LazyVStack(spacing: AppTheme.Spacing.section) {
                            FlipCard(
                                front: AnyView(PassportHeaderView(
                                    stats: stats,
                                    onArchetypeTap: { withAnimation(AppTheme.Animation.springGentle) { showSpectrum = true } }
                                )),
                                back: AnyView(
                                    SpectrumView(items: stats.barcodeData)
                                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                                ),
                                isFlipped: showSpectrum
                            )
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    let card = PassportCardView(stats: stats)
                                    if let image = card.renderToImage() {
                                        shareImage = image
                                        showingShareSheet = true
                                    }
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .padding(6)
                                        .background(Circle().fill(.ultraThinMaterial))
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .help("Share Passport")
                                .padding(12)
                            }
                            .onTapGesture {
                                withAnimation(AppTheme.Animation.springGentle) {
                                    showSpectrum.toggle()
                                }
                            }

                            SectionDivider(color: AppTheme.Colors.accent)

                            switch selectedTab {
                            case .overview:
                                overviewContent(stats: stats)
                            case .browse:
                                browseContent(stats: stats)
                            }
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
                    .scrollIndicators(.hidden)
                    .background {
                        ScrollVelocityTracker(isFastScrolling: $isFastScrolling, scrollTask: $scrollTask)
                    }
                    .onPreferenceChange(ScrollOffsetKey.self) { offsets in
                        let newOffset = offsets[insightsScrollName] ?? 0
                        scrollOffset = newOffset
                        backgroundTintTask?.cancel()
                        backgroundTintTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 50_000_000)
                            guard !Task.isCancelled else { return }
                            scrollOffsetDebounced = newOffset
                        }
                    }
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
            backgroundTintTask?.cancel()
            backgroundTintTask = nil
        }
        .onChange(of: showingShareSheet) { _, show in
            if show, let image = shareImage {
                let picker = NSSharingServicePicker(items: [image])
                if let window = NSApp.keyWindow, let content = window.contentView {
                    picker.show(relativeTo: .zero, of: content, preferredEdge: .minY)
                }
                showingShareSheet = false
            }
        }
    }

    @ViewBuilder
    private func overviewContent(stats: LibraryStats) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.large) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                SectionHeader(title: "Overview", icon: "chart.bar.fill", iconColor: AppTheme.Colors.accent)
                HeroStatPills(stats: stats)
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                SectionHeader(title: "Taste DNA", icon: "heart.circle.fill", iconColor: AppTheme.Colors.accent)
                TasteDNAView(stats: stats)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)

        HStack(alignment: .top, spacing: AppTheme.Spacing.large) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                SectionHeader(title: "Watch Streak", icon: "flame.fill", iconColor: .orange)
                StreakSummaryView(stats: stats)
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                SectionHeader(title: "Mood Journey", icon: "heart.text.clipboard.fill", iconColor: AppTheme.Colors.accent)
                MoodTimelineView(stats: stats)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)

        SectionDivider(color: AppTheme.Colors.accent)

        HallOfFameView(stats: stats)
    }

    @ViewBuilder
    private func browseContent(stats: LibraryStats) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            SectionHeader(title: "Genre Constellation", icon: "sparkles", iconColor: AppTheme.Colors.accent)
            GenreConstellationView(items: Array(stats.genreDNA.prefix(8)))
        }

        SectionDivider(color: AppTheme.Colors.accent)

        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            SectionHeader(title: "Streaming Providers", icon: "tv.and.mediabox.fill", iconColor: AppTheme.Colors.accent)
            ProviderRingView(providers: stats.topProviders, providerCoverage: stats.providerCoverage)
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
        }

        SectionDivider(color: AppTheme.Colors.accent)

        StudiosNetworksView(stats: stats, modelContext: modelContext)
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

// MARK: - Insight Tab Pill

private struct InsightTabPill: View {
    let tab: InsightTab
    @Binding var selectedTab: InsightTab
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    private var isActive: Bool { selectedTab == tab }

    var body: some View {
        Button {
            withAnimation(AppTheme.Animation.springGentle) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(AppTheme.Font.caption2)
                Text(tab.rawValue)
                    .font(AppTheme.Font.caption)
                    .fontWeight(isActive ? .semibold : .regular)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(isActive ? .white : .primary.opacity(0.7))
            .background {
                ZStack {
                    if isActive {
                        Capsule()
                            .fill(AppTheme.Colors.accent)
                            .shadow(color: AppTheme.Colors.accent.opacity(0.3), radius: 4, y: 2)
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Capsule()
                                    .stroke(.primary.opacity(0.06), lineWidth: 0.5)
                            }
                    }
                }
            }
            .scaleEffect(isHovered ? 1.04 : 1.0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.springSnappy) {
                isHovered = hovering
            }
        }
    }
}
