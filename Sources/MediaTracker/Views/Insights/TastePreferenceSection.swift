import SwiftUI

/// Left section of the Taste Profile card — the three preference rows
/// (Top Genre, Top Network, Top Studio).
struct TastePreferenceSection: View {
    let stats: LibraryStats
    let topNetworkName: String
    let topStudioName: String
    let topNetworkLogoPath: String?
    let topStudioLogoPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let items: [(title: String, value: String, score: Double?, logo: String?, emoji: String, color: Color)] = [
                ("Top Genre",   stats.genreDNA.first?.name ?? stats.topGenre ?? "—",
                 stats.genreDNA.first.map { $0.percentage / 100 }, nil, "🎬", .pink),
                ("Top Network", topNetworkName,  stats.topRatedNetworks.first?.score, topNetworkLogoPath, "📡", .purple),
                ("Top Studio",  topStudioName,   stats.topRatedStudios.first?.score,  topStudioLogoPath,  "🏢", .indigo),
            ]
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                TastePreferenceRow(
                    title: item.title,
                    value: item.value,
                    score: item.score,
                    logoPath: item.logo,
                    fallbackEmoji: item.emoji,
                    accentColor: item.color
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Flat Preference Row

/// Flat preference row: no card background, just logo/emoji + label + affinity bar.
private struct TastePreferenceRow: View {
    let title: String
    let value: String
    let score: Double?
    let logoPath: String?
    let fallbackEmoji: String
    let accentColor: Color

    @Environment(\.colorScheme) var colorScheme

    private var logoURL: URL? {
        guard let logoPath,
              let urlString = APIClient.tmdbImageURL(path: logoPath, size: "w300")
        else { return nil }
        return URL(string: urlString)
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            // Logo or emoji
            ZStack {
                if let url = logoURL {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
                        CachedImage(url: url, targetSize: CGSize(width: 44, height: 24), priority: .low) { _ in
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.08))
                        }
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 22)
                        .padding(3)
                    }
                    .frame(width: 48, height: 30)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12))
                        Text(fallbackEmoji)
                            .font(.system(size: 16))
                    }
                    .frame(width: 36, height: 36)
                }
            }

            // Label + value
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .kerning(0.5)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: AppTheme.Spacing.small)

            // Affinity bar
            if let score, score > 0 {
                affinityMeter(score: score)
            }
        }
        .padding(.vertical, AppTheme.Spacing.small)
    }

    private func affinityMeter(score: Double) -> some View {
        HStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.7)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(min(max(score, 0), 1)))
                }
            }
            .frame(width: 48, height: 5)

            Text(String(format: "%.0f%%", score * 100))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
