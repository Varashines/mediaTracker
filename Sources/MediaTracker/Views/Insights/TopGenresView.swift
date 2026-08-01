import SwiftUI

private func genreIconAndColor(_ name: String) -> (icon: String, color: Color) {
    let lower = name.lowercased()
    if lower.contains("action") || lower.contains("adventure") { return ("flame.fill", .orange) }
    if lower.contains("comedy") { return ("face.smiling.fill", .yellow) }
    if lower.contains("drama") { return ("theatermasks.fill", .indigo) }
    if lower.contains("horror") || lower.contains("thriller") { return ("bolt.heart.fill", .red) }
    if lower.contains("romance") { return ("heart.fill", .pink) }
    if lower.contains("sci-fi") || lower.contains("science") { return ("atom", .cyan) }
    if lower.contains("fantasy") || lower.contains("animation") { return ("sparkles", .purple) }
    if lower.contains("crime") || lower.contains("mystery") { return ("magnifyingglass", .teal) }
    if lower.contains("documentary") || lower.contains("history") { return ("book.closed.fill", .brown) }
    if lower.contains("family") { return ("house.fill", .green) }
    if lower.contains("music") || lower.contains("musical") { return ("music.note", .mint) }
    return ("film.fill", .blue)
}

struct TopGenresView: View {
    let items: [(name: String, percentage: Double)]

    var body: some View {
        if items.isEmpty {
            emptyState
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.large) {
                    ForEach(Array(items.prefix(6).enumerated()), id: \.element.name) { index, item in
                        GenrePillCard(rank: index + 1, name: item.name, percentage: item.percentage)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.vertical, 4)
            }
        }
    }

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 10) {
                Circle()
                    .fill(AppTheme.Colors.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.accent)
                    }
                Text("Discovering Your Top Genres")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Watch at least 10 titles in a genre to unlock your personalized taste cards.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
    }
}

private struct GenrePillCard: View {
    let rank: Int
    let name: String
    let percentage: Double
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    private var style: (icon: String, color: Color) {
        genreIconAndColor(name)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 4) {
                Image(systemName: style.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(style.color)

                Text(name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if isHovered {
                    Text("\(Int(round(percentage)))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(style.color)
                        .transition(.opacity)
                }
            }

            Text("\(rank)")
                .font(.system(size: 70, weight: .black, design: .rounded))
                .foregroundStyle(style.color.opacity(isHovered ? 0.22 : 0.10))
                .offset(x: -10, y: -6)
                .allowsHitTesting(false)
        }
        .frame(width: 160, height: 90)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(isHovered ? style.color.opacity(colorScheme == .dark ? 0.06 : 0.03) : AppTheme.Colors.cardFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(style.color.opacity(isHovered ? 0.25 : 0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0), radius: 8, y: isHovered ? 4 : 0)
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onHover { isHovered = $0 }
    }
}
