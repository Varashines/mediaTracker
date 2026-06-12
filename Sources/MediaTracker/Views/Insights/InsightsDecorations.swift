import SwiftUI

// MARK: - Reusable Decorations

struct CuteEmptyState: View {
    let icon: String
    let message: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(color)
            Text(message)
                .font(AppTheme.Font.body)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }
}

struct MedalBadge: View {
    let rank: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(rank == 1 ? Color.yellow.opacity(0.2) : rank == 2 ? Color.gray.opacity(0.2) : rank == 3 ? Color.orange.opacity(0.2) : Color.clear)
                .frame(width: 22, height: 22)
            Text(rank == 1 ? "🥇" : rank == 2 ? "🥈" : rank == 3 ? "🥉" : "\(rank)")
                .font(.system(size: rank <= 3 ? 12 : 10, weight: .bold, design: .rounded))
        }
    }
}

struct ArchetypeBadge: View {
    let archetype: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: archetypeIcon)
                .font(.system(size: 12, weight: .semibold))
            Text(archetype)
                .font(AppTheme.Font.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .foregroundStyle(.primary)
        .background(
            Capsule()
                .fill(AppTheme.Colors.accent.opacity(colorScheme == .dark ? 0.15 : 0.1))
        )
        .overlay(
            Capsule()
                .stroke(AppTheme.Colors.accent.opacity(0.3), lineWidth: 0.5)
        )
    }

    private var archetypeIcon: String {
        switch archetype {
        case "The Completionist": return "checkmark.seal.fill"
        case "The Explorer": return "binoculars.fill"
        case "The Binger": return "play.rectangle.on.rectangle.fill"
        case "The Curator": return "sparkles.rectangle.stack.fill"
        case "The Newcomer": return "star.fill"
        default: return "heart.fill"
        }
    }
}

struct SparklineShape: Shape {
    let data: [Double]
    let maxValue: Double?

    func path(in rect: CGRect) -> Path {
        guard data.count > 1 else { return Path() }
        let max = maxValue ?? data.max() ?? 1
        guard max > 0 else { return Path() }
        let stepX = rect.width / CGFloat(data.count - 1)
        var path = Path()
        for (i, value) in data.enumerated() {
            let x = CGFloat(i) * stepX
            let y = rect.height - (CGFloat(value) / CGFloat(max)) * rect.height
            let point = CGPoint(x: x, y: y)
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

struct MiniBarChart: View {
    let items: [(label: String, value: Int, color: Color)]
    let maxValue: Int

    var body: some View {
        let max = maxValue > 0 ? maxValue : items.map { $0.value }.max() ?? 1
        VStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 8) {
                    Text(item.label)
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(item.color.gradient)
                                .frame(width: geo.size.width * CGFloat(item.value) / CGFloat(max), height: 8)
                        }
                    }
                    .frame(height: 8)
                    Text("\(item.value)")
                        .font(AppTheme.Font.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
            }
        }
    }
}

struct PersonalityBadge: View {
    let personality: String

    var body: some View {
        let color: Color = {
            switch personality {
            case "Hopeless Romantic": return .pink
            case "Harsh Critic": return .orange
            case "Enthusiast": return .green
            case "Mystery Critic": return .gray
            default: return .blue
            }
        }()

        HStack(spacing: 4) {
            Image(systemName: "face.smiling")
                .font(.system(size: 10, weight: .medium))
            Text(personality)
                .font(AppTheme.Font.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 0.5))
    }
}

struct CountUpText: View {
    let value: String
    @State private var opacity: Double = 0
    @State private var offset: CGFloat = 8

    var body: some View {
        Text(value)
            .opacity(opacity)
            .offset(y: offset)
            .onAppear {
                withAnimation(AppTheme.Animation.springGentle) {
                    opacity = 1
                    offset = 0
                }
            }
    }
}

struct InsightGlassTile<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    @ViewBuilder let content: Content
    @State private var isHovered = false

    var body: some View {
        content
            .padding(AppTheme.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .fill(AppTheme.Colors.cardFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 0.5)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .shadow(color: Color.black.opacity(isHovered ? 0.06 : 0), radius: 8, x: 0, y: 4)
            .onHover { hovering in
                withAnimation(AppTheme.Animation.springSnappy) { isHovered = hovering }
            }
    }
}

// MARK: - Dashboard Card (used by DonutChart.swift)

struct DashboardCard<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(AppTheme.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Colors.cardFill(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), lineWidth: 0.5)
            )
    }
}
