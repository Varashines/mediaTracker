import SwiftUI

struct MoodCaptureBanner: View {
    var mediaType: MediaType? = nil
    let onSelectMood: (Mood) -> Void
    let onDismiss: () -> Void
    @State private var appears = false
    @State private var dismissWork: DispatchWorkItem?
    @State private var hoveredMood: Mood? = nil
    @Environment(\.colorScheme) var colorScheme

    private var moods: [Mood] { Mood.moods(for: mediaType) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(spacing: AppTheme.Spacing.smallMedium) {
            // Cute Header
            HStack(spacing: AppTheme.Spacing.tiny) {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.accent.opacity(0.18))
                        .frame(width: 28, height: 28)

                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.accent)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("How did it feel?")
                        .font(AppTheme.Font.subtitle)
                        .foregroundStyle(.primary)
                    Text("Tap an emotion to capture your vibe")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismissWork?.cancel()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        appears = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onDismiss()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("Skip")
                            .font(AppTheme.Font.caption)
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.Spacing.tiny)
            .opacity(appears || AppThemeCoordinator.isReducingVisualEffects ? 1 : 0)

            // Cute 3×3 Mood Grid
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(moods.enumerated()), id: \.element) { index, mood in
                    moodButton(mood)
                        .opacity(appears || AppThemeCoordinator.isReducingVisualEffects ? 1 : 0)
                        .offset(y: appears || AppThemeCoordinator.isReducingVisualEffects ? 0 : 12)
                        .if(!AppThemeCoordinator.isReducingVisualEffects) {
                            $0.animation(.spring(response: 0.4, dampingFraction: 0.7).delay(Double(index) * 0.04), value: appears)
                        }
                }
            }
        }
        .padding(AppTheme.Spacing.medium)
        .background(
            ZStack {
                if let hovered = hoveredMood {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                        .fill(hovered.color.opacity(0.06))
                        .transition(.opacity)
                }

                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .fill(AppThemeCoordinator.isReducingVisualEffects
                        ? AnyShapeStyle(AppTheme.Colors.background(for: colorScheme))
                        : AnyShapeStyle(.ultraThinMaterial))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke((hoveredMood?.color ?? AppTheme.Colors.accent).opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
        .offset(y: appears ? 0 : -30)
        .opacity(appears ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: appears)
        .onAppear {
            appears = true
            let task = DispatchWorkItem {
                withAnimation(.easeInOut(duration: 0.3)) {
                    appears = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDismiss()
                }
            }
            dismissWork = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: task)
        }
        .onDisappear { dismissWork?.cancel() }
    }

    private func moodButton(_ mood: Mood) -> some View {
        let isHovered = hoveredMood == mood

        return Button {
            dismissWork?.cancel()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                appears = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onSelectMood(mood)
            }
        } label: {
            HStack(spacing: 8) {
                Text(mood.emojiChar)
                    .font(.system(size: 20))
                    .scaleEffect(isHovered ? 1.2 : 1.0)

                Text(mood.rawValue)
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(isHovered ? mood.color : .primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.Spacing.smallMedium)
            .padding(.vertical, AppTheme.Spacing.compact)
            .background(
                Capsule()
                    .fill(mood.color.opacity(isHovered ? 0.22 : 0.08))
            )
            .overlay(
                Capsule()
                    .stroke(mood.color.opacity(isHovered ? 0.5 : 0.15), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .shadow(color: isHovered ? mood.color.opacity(0.2) : .clear, radius: 6, y: 3)
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onHover { hovering in
            hoveredMood = hovering ? mood : nil
        }
    }
}
