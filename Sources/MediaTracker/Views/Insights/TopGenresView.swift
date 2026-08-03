import SwiftUI

private func genreColor(_ name: String) -> Color {
    let lower = name.lowercased()
    if lower.contains("action") || lower.contains("adventure") { return .orange }
    if lower.contains("comedy") { return .yellow }
    if lower.contains("drama") { return .indigo }
    if lower.contains("horror") || lower.contains("thriller") { return .red }
    if lower.contains("romance") { return .pink }
    if lower.contains("sci-fi") || lower.contains("science") { return .cyan }
    if lower.contains("fantasy") || lower.contains("animation") { return .purple }
    if lower.contains("crime") || lower.contains("mystery") { return .teal }
    if lower.contains("documentary") || lower.contains("history") { return .brown }
    if lower.contains("family") { return .green }
    if lower.contains("music") || lower.contains("musical") { return .mint }
    return .blue
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

    private var color: Color {
        genreColor(name)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 4) {
                Text(name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if isHovered {
                    Text("\(Int(round(percentage)))% taste match")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                        .transition(.opacity)
                }
            }

            Text("\(rank)")
                .font(.system(size: 70, weight: .black, design: .rounded))
                .foregroundStyle(color.opacity(isHovered ? 0.22 : 0.10))
                .offset(x: -10, y: -6)
                .allowsHitTesting(false)
        }
        .frame(width: 160, height: 90)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(isHovered ? color.opacity(colorScheme == .dark ? 0.06 : 0.03) : AppTheme.Colors.cardFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(color.opacity(isHovered ? 0.25 : 0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0), radius: 8, y: isHovered ? 4 : 0)
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onHover { isHovered = $0 }
    }
}
