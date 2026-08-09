import SwiftUI

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
        .contentShape(Capsule())
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

// MARK: - Section Card (Cinema DNA signature style)

/// Section container matching the Cinema DNA (SpectrumView) card exactly:
/// title header inside the card, monospaced all-caps, accent tint fill,
/// subtle stroke, identical internal padding.
struct InsightsSectionCard<Content: View>: View {
    let title: String
    var secondLine: String? = nil
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.top, AppTheme.Spacing.medium)
                .padding(.bottom, AppTheme.Spacing.small)

            content()
                .padding(.bottom, AppTheme.Spacing.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .fill(AppTheme.Colors.accent.opacity(colorScheme == .dark ? 0.07 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(AppTheme.Colors.accent.opacity(0.16), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .foregroundStyle(AppTheme.Colors.accent)
            if let secondLine {
                Text(secondLine.uppercased())
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
        }
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
