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
    @State private var scrollOffsetDebounced: CGFloat = 0
    @State private var isFastScrolling = false
    @State private var scrollTask: Task<Void, Never>?
    @State private var backgroundTintTask: Task<Void, Never>?
    @State private var showingShareSheet = false
    @State private var shareImage: NSImage? = nil
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
                ScrollView {
                    LazyVStack(spacing: AppTheme.Spacing.section) {

                        // ── Section 1: Overview ──────────────────────────
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                            SectionHeader(title: "Overview", icon: "chart.bar.fill", iconColor: AppTheme.Colors.accent)
                            
                            HeroStatPills(stats: stats)
                                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        }

                        SectionDivider(color: AppTheme.Colors.accent)

                        // ── Section 2: Taste DNA ──────────────────────────
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                            SectionHeader(title: "Taste DNA", icon: "heart.circle.fill", iconColor: AppTheme.Colors.accent)
                            TasteDNAView(stats: stats)
                                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        }

                        SectionDivider(color: AppTheme.Colors.accent)

                        // ── Section 4: Genre Constellation (bubble chart) ──
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                            SectionHeader(title: "Genre Constellation", icon: "sparkles", iconColor: AppTheme.Colors.accent)
                            GenreConstellationView(items: Array(stats.genreDNA.prefix(5)))
                        }

                        SectionDivider(color: AppTheme.Colors.accent)

                        // ── Section 5: Hall of Fame (carousel) ────────────
                        HallOfFameView(stats: stats)

                        SectionDivider(color: AppTheme.Colors.accent)

                        // ── Section 6: Streaming DNA (unified tab switcher) ─
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                            SectionHeader(title: "Streaming DNA", icon: "tv.and.mediabox.fill", iconColor: AppTheme.Colors.accent)
                            StreamingDNAView(stats: stats, modelContext: modelContext)
                        }

                        SectionDivider(color: AppTheme.Colors.accent)

                        // ── Section 7: Cinema Spectrum ────────────────────
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                            SectionHeader(title: "Cinema Signature", icon: "barcode", iconColor: AppTheme.Colors.accent)
                            SpectrumView(items: stats.barcodeData)
                                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        }

                        SectionDivider(color: AppTheme.Colors.accent)

                        // ── Section 8: Cinema Passport (collectible) ──────
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                            SectionHeader(title: "Cinema Passport", icon: "wallet.pass.fill", iconColor: AppTheme.Colors.accent)

                            PassportHeaderView(stats: stats)

                            HStack {
                                Spacer()
                                Button {
                                    let card = PassportCardView(stats: stats)
                                    if let image = card.renderToImage() {
                                        shareImage = image
                                        showingShareSheet = true
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("Share Passport")
                                            .font(AppTheme.Font.bodyBold)
                                    }
                                    .foregroundStyle(AppTheme.Colors.accent)
                                    .padding(.horizontal, AppTheme.Spacing.medium)
                                    .padding(.vertical, AppTheme.Spacing.tiny)
                                    .background(
                                        Capsule()
                                            .fill(AppTheme.Colors.accent.opacity(0.10))
                                            .overlay(
                                                Capsule()
                                                    .stroke(AppTheme.Colors.accent.opacity(0.25), lineWidth: 0.8)
                                            )
                                    )
                                    .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                Spacer()
                            }
                            .padding(.horizontal, AppTheme.Spacing.pageMargin)
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
