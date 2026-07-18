import SwiftUI

struct MoodCaptureBanner: View {
    let onSelectMood: (Mood) -> Void
    let onDismiss: () -> Void
    @State private var appears = false
    @State private var dismissWork: DispatchWorkItem?
    @State private var hoveredMood: Mood? = nil
    @Environment(\.colorScheme) var colorScheme

    private let moods = Mood.allCases
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(spacing: AppTheme.Spacing.compact) {
            // Prompt
            VStack(spacing: 4) {
                Text("How did it feel?")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(.primary)
                Text("Capture your emotional response")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.tertiary)
            }
            .opacity(appears || AppThemeCoordinator.isReducingVisualEffects ? 1 : 0)
            .offset(y: appears || AppThemeCoordinator.isReducingVisualEffects ? 0 : -8)

            // 2×3 mood grid
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(moods.enumerated()), id: \.element) { index, mood in
                        moodButton(mood)
                            .opacity(appears || AppThemeCoordinator.isReducingVisualEffects ? 1 : 0)
                            .offset(y: appears || AppThemeCoordinator.isReducingVisualEffects ? 0 : 12)
                            .if(!AppThemeCoordinator.isReducingVisualEffects) {
                                $0.animation(.spring(response: 0.4, dampingFraction: 0.7).delay(Double(index) * 0.05), value: appears)
                            }
                    }
                }

            // Skip
            Button("Skip") {
                dismissWork?.cancel()
                withAnimation(.easeInOut(duration: 0.25)) {
                    appears = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onDismiss()
                }
            }
            .font(AppTheme.Font.caption)
            .foregroundStyle(.tertiary)
            .buttonStyle(.plain)
            .opacity(appears ? 1 : 0)
        }
        .padding(.vertical, AppTheme.Spacing.medium)
        .padding(.horizontal, AppTheme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .fill(AppThemeCoordinator.isReducingVisualEffects
                    ? AnyShapeStyle(AppTheme.Colors.background(for: colorScheme))
                    : AnyShapeStyle(.ultraThinMaterial))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
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
        Button {
            dismissWork?.cancel()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                appears = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onSelectMood(mood)
            }
        } label: {
            VStack(spacing: 4) {
                Text(mood.emojiChar)
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(mood.color.opacity(0.12))
                    )
                    .overlay(
                        Circle()
                            .stroke(mood.color.opacity(0.2), lineWidth: 0.5)
                    )
                    .shadow(color: mood.color.opacity(0.15), radius: 6)
                Text(mood.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .scaleEffect(1.0)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .scaleEffect(hoveredMood == mood ? 1.05 : 1.0)
        .animation(AppTheme.Animation.springSnappy, value: hoveredMood == mood)
        .onHover { hovering in
            hoveredMood = hovering ? mood : nil
        }
    }
}
