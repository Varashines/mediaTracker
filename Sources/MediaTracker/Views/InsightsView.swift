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
    @State private var customPassportImage: NSImage? = nil
    @State private var showCustomShareMenu = false
    @State private var showPassportPreview = false
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
                        SpectrumView(items: stats.barcodeData)
                            .padding(.horizontal, AppTheme.Spacing.pageMargin)

                        SectionDivider(color: AppTheme.Colors.accent)

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                            SectionHeader(title: "Overview", icon: "chart.bar.fill", iconColor: AppTheme.Colors.accent)
                            HeroStatPills(stats: stats)
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)

                        SectionDivider(color: AppTheme.Colors.accent)

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                            SectionHeader(title: "Taste DNA", icon: "heart.circle.fill", iconColor: AppTheme.Colors.accent)
                            TasteDNAView(stats: stats)
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)

                        SectionDivider(color: AppTheme.Colors.accent)

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                            SectionHeader(title: "Top Genres", icon: "sparkles", iconColor: AppTheme.Colors.accent)
                            TopGenresView(items: Array(stats.genreDNA.prefix(6)))
                        }

                        SectionDivider(color: AppTheme.Colors.accent)

                        StudiosNetworksView(stats: stats, modelContext: modelContext)

                        SectionDivider(color: AppTheme.Colors.accent)

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
        .saturation(showPassportPreview ? 0.3 : 1)
        .blur(radius: showPassportPreview ? 5 : 0)
        .animation(AppTheme.Animation.springSnappy, value: showPassportPreview)
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if stats != nil {
                    Button {
                        withAnimation(AppTheme.Animation.springSnappy) { showPassportPreview = true }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .help("Share Cinema Wrapped Passport (⌘S)")
                }
            }
        }
        .overlay {
            if showPassportPreview, let stats {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(AppTheme.Animation.springSnappy) { showPassportPreview = false } }
                        .transition(.opacity)

                    VStack(spacing: 16) {
                        HStack {
                            Text("CINEMA WRAPPED PASSPORT")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .kerning(1.5)
                                .foregroundStyle(.white.opacity(0.85))

                            Spacer()

                            Button {
                                withAnimation(AppTheme.Animation.springSnappy) { showPassportPreview = false }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white.opacity(0.4), .white.opacity(0.12))
                            }
                            .buttonStyle(.plain)
                            .contentShape(Circle())
                            .help("Close")
                        }

                        PassportCardView(stats: stats)
                            .scaleEffect(0.85)
                            .frame(width: 420 * 0.85, height: 630 * 0.85)
                            .environment(\.colorScheme, .dark)
                            .shadow(color: .black.opacity(0.45), radius: 24, y: 12)

                        Button {
                            let card = PassportCardView(stats: stats)
                            if let image = card.renderToImage() {
                                customPassportImage = image
                                withAnimation(AppTheme.Animation.springSnappy) { showCustomShareMenu = true }
                            }
                        } label: {
                            Label("Share Passport", systemImage: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(AppTheme.Colors.accent))
                        }
                        .buttonStyle(.plain)
                        .contentShape(Capsule())
                        .shadow(color: AppTheme.Colors.accent.opacity(0.35), radius: 8, y: 4)
                    }
                    .padding(20)
                    .frame(width: 410)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color(white: 0.08).opacity(0.95))
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.6), radius: 30, y: 15)
                    )

                    if showCustomShareMenu, let img = customPassportImage {
                        ZStack {
                            Color.black.opacity(0.4)
                                .ignoresSafeArea()
                                .onTapGesture { showCustomShareMenu = false }

                            CustomShareMenuView(image: img, title: "Cinema_Wrapped_Passport") {
                                showCustomShareMenu = false
                                showPassportPreview = false
                            }
                        }
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                }
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(AppTheme.Animation.springSnappy, value: showPassportPreview)
        .animation(AppTheme.Animation.springSnappy, value: showCustomShareMenu)
    }

    private func refreshData() {
        statsTask?.cancel()
        statsTask = Task {
            let actor = LibraryStatsActor(modelContainer: modelContext.container)
            do {
                let result = try await actor.fetchStats(includeCinephileData: true)
                try? await Task.sleep(nanoseconds: 350_000_000)
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
