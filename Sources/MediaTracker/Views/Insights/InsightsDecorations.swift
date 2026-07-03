import SwiftUI

// MARK: - Reusable Decorations

struct SectionDivider: View {
    let color: Color
    @State private var hasAppeared = false

    var body: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [color.opacity(0.35), color.opacity(0.0)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
            .frame(width: hasAppeared ? 200 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
            .onAppear {
                withAnimation(AppTheme.Animation.easeInOut.delay(0.1)) {
                    hasAppeared = true
                }
            }
    }
}

// MARK: - Archetype & Personality Badges

struct ArchetypeBadge: View {
    let archetype: String
    var onTap: (() -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: archetypeIcon)
                    .font(AppTheme.Font.label)
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
        .buttonStyle(.plain)
    }

    private var archetypeIcon: String {
        switch archetype {
        case let s where s.contains("Connoisseur"): return "sparkles"
        case let s where s.contains("Completionist"): return "checkmark.seal.fill"
        case let s where s.contains("Explorer"): return "binoculars.fill"
        case let s where s.contains("Binger"): return "play.rectangle.on.rectangle.fill"
        case let s where s.contains("Collector"): return "books.vertical.fill"
        case let s where s.contains("Critic"): return "hand.thumbsdown.fill"
        case let s where s.contains("Streamer"): return "antenna.radiowaves.left.and.right"
        case let s where s.contains("Newcomer"): return "star.fill"
        case let s where s.contains("Enthusiast"): return "heart.fill"
        default: return "heart.fill"
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
                .font(AppTheme.Font.label)
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

struct CuteEmptyState: View {
    let icon: String
    let message: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(AppTheme.Font.title3)
                .foregroundStyle(color)
            Text(message)
                .font(AppTheme.Font.body)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
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

// MARK: - Flip Card with Solari Strip Lines

struct FlipCard<Front: View, Back: View>: View {
    let front: Front
    let back: Back
    let isFlipped: Bool
    var stripCount: Int = 8

    var body: some View {
        ZStack {
            if !isFlipped {
                front
            }

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
