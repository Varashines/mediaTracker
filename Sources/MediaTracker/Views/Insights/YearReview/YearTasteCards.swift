import SwiftUI

/// Taste cards computed ONLY from the set of 2026-released titles the user
/// watched — not their general library taste.
struct YearTasteCards: View {
    let genres: [(name: String, score: Double)]
    let networks: [(name: String, count: Int)]
    let actors: [ScoredPerson]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if genres.isEmpty && networks.isEmpty && actors.isEmpty {
            CuteEmptyState(
                icon: "sparkles.tv",
                message: "Watch a few 2026 releases and your year taste will build here.",
                color: AppTheme.Colors.accent
            )
        } else {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                if !genres.isEmpty {
                    tasteBlock("Top Genres of 2026") {
                        HStack(spacing: AppTheme.Spacing.tiny) {
                            ForEach(genres.prefix(5), id: \.name) { genre in
                                genrePill(genre)
                            }
                        }
                    }
                }

                if !networks.isEmpty {
                    tasteBlock("Networks You Binged") {
                        HStack(spacing: AppTheme.Spacing.tiny) {
                            ForEach(networks.prefix(3), id: \.name) { network in
                                networkPill(network)
                            }
                        }
                    }
                }

                if !actors.isEmpty {
                    tasteBlock("Actors of Your 2026") {
                        HStack(spacing: AppTheme.Spacing.small) {
                            ForEach(actors.prefix(5), id: \.id) { actor in
                                actorCell(actor)
                            }
                        }
                    }
                }
            }
        }
    }

    private func tasteBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text(title.uppercased())
                .font(AppTheme.Font.tiny)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func genrePill(_ genre: (name: String, score: Double)) -> some View {
        HStack(spacing: 4) {
            Text(genre.name)
                .font(AppTheme.Font.caption2)
            Text("\(Int(genre.score * 100))%")
                .font(AppTheme.Font.small)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.vertical, AppTheme.Spacing.mini)
        .background(Capsule().fill(AppTheme.Colors.accent.opacity(colorScheme == .dark ? 0.15 : 0.1)))
        .overlay(Capsule().stroke(AppTheme.Colors.accent.opacity(0.3), lineWidth: 0.5))
    }

    private func networkPill(_ network: (name: String, count: Int)) -> some View {
        HStack(spacing: 4) {
            Text(network.name)
                .font(AppTheme.Font.caption2)
            Text("\(network.count)")
                .font(AppTheme.Font.small)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.vertical, AppTheme.Spacing.mini)
        .background(Capsule().fill(.secondary.opacity(0.12)))
        .overlay(Capsule().stroke(.secondary.opacity(0.2), lineWidth: 0.5))
    }

    private func actorCell(_ actor: ScoredPerson) -> some View {
        VStack(spacing: AppTheme.Spacing.micro) {
            if let url = actor.profileURL, let url = URL(string: url) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(.secondary.opacity(0.2))
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(AppTheme.Colors.accent.opacity(colorScheme == .dark ? 0.25 : 0.15))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(String(actor.name.prefix(1)).uppercased())
                            .font(AppTheme.Font.title3)
                            .foregroundStyle(AppTheme.Colors.accent)
                    )
            }

            Text(actor.name)
                .font(AppTheme.Font.caption2)
                .lineLimit(1)
                .frame(width: 60)
            Text("\(Int(actor.score * 100))%")
                .font(AppTheme.Font.small)
                .foregroundStyle(.secondary)
        }
        .frame(width: 60)
    }
}
