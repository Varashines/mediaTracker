import SwiftUI
import SwiftData

struct CinephileLabDestination: Hashable {}

struct CinephileLabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var stats: LibraryStats?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                CinephileLabSkeletonView()
            } else if let stats = stats {
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.section) {
                        // Cinephile Spectrum (Barcode)
                        CinephileBarcodeView(items: stats.barcodeData)
                            .padding(.horizontal, AppTheme.Spacing.pageMargin)

                        // Top Genres
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                            SectionHeader(title: "Top Genres", icon: "sparkles", iconColor: .indigo)
                            TopGenresView(items: Array(stats.genreDNA.prefix(10)))
                        }

                        // Top Studios
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                            SectionHeader(title: "Top Studios", icon: "building.2.fill", iconColor: .orange)
                            TopBrandsHorizontalView(items: stats.topRatedStudios, color: .orange, icon: "building.2.fill")
                        }

                        // Top Networks
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                            SectionHeader(title: "Top Networks", icon: "antenna.radiowaves.left.and.right", iconColor: .teal)
                            TopBrandsHorizontalView(items: stats.topRatedNetworks, color: .teal, icon: "antenna.radiowaves.left.and.right")
                        }
                    }
                    .padding(.vertical, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
                .navigationTitle("Cinephile Lab")
            }
        }
        .task { await fetchData() }
    }

    private func fetchData() async {
        let actor = LibraryStatsActor(modelContainer: modelContext.container)
        do {
            if let fullStats = try await actor.fetchCinephileData() {
                self.stats = fullStats
            }
        } catch {
            AppLogger.debug("Error fetching cinephile data: \(error)")
        }

        try? await Task.sleep(nanoseconds: 350_000_000)
        withAnimation(.easeInOut(duration: 0.3)) { isLoading = false }
    }
}

// MARK: - Top Genres (Gallery Grid Tiles)

struct GalleryCardView: View {
    let name: String
    let value: Double
    let rank: Int
    let color: Color
    let icon: String

    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)

            ZStack {
                // Rank number shown by default
                Text(String(format: "%02d", rank))
                    .font(AppTheme.Font.titleLarge)
                    .foregroundStyle(color.gradient)
                    .opacity(isHovered ? 0.0 : 1.0)
                    .scaleEffect(1.0)

                // Percentage shown on hover
                Text(String(format: "%.0f%%", value * 100))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .opacity(isHovered ? 1.0 : 0.0)
                    .scaleEffect(1.0)
            }
            .animation(AppTheme.Animation.springSnappy, value: isHovered)
            .frame(height: 32)

            Spacer(minLength: 0)

            Text(name)
                .font(AppTheme.Font.caption)
                .foregroundStyle(.primary.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 6)
                .frame(height: 28, alignment: .center)
        }
        .padding(.vertical, 8)
        .frame(width: 104, height: 90)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.cardFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isHovered
                        ? AnyShapeStyle(color.gradient)
                        : AnyShapeStyle(AppTheme.Colors.cardFill(for: colorScheme)),
                    lineWidth: isHovered ? 1.5 : 0.7
                )
        )
        .shadow(color: color.opacity(isHovered ? 0.12 : 0.0), radius: 6, x: 0, y: 3)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.springSnappy) {
                isHovered = hovering
            }
        }
    }
}

struct TopGenresView: View {
    let items: [(name: String, percentage: Double)]

    private var palette: [Color] {
        [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .mint, .red, .yellow]
    }

    var body: some View {
        if items.isEmpty {
            HStack {
                Spacer()
                Text("No genre data")
                    .font(AppTheme.Font.body)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(height: 50)
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(items.prefix(10).enumerated()), id: \.element.name) { idx, item in
                        let color = palette[idx % palette.count]
                        GalleryCardView(name: item.name, value: item.percentage, rank: idx + 1, color: color, icon: "film.fill")
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.vertical, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - Top Brands Horizontal Scroll

struct TopBrandsHorizontalView: View {
    let items: [(name: String, score: Double)]
    let color: Color
    let icon: String

    var body: some View {
        if items.isEmpty {
            HStack {
                Spacer()
                Text("No statistics available")
                    .font(AppTheme.Font.body)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(height: 50)
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(items.prefix(10).enumerated()), id: \.element.name) { idx, item in
                        GalleryCardView(name: item.name, value: item.score, rank: idx + 1, color: color, icon: icon)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.vertical, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

struct CinephileLabSkeletonView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.section) {
                // 1. Cinephile Spectrum (Barcode) Skeleton
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 140, height: 16)
                        Spacer()
                    }
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 60)
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)

                // 2. Top Genres Skeleton
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 100, height: 16)
                        Spacer()
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<5, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 104, height: 90)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    }
                }

                // 3. Top Studios/Networks Skeleton
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 130, height: 16)
                        Spacer()
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 180, height: 80)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    }
                }
            }
            .padding(.vertical, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .shimmering()
    }
}

#Preview("Cinephile Lab") {
    CinephileLabView()
}
