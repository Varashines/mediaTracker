import SwiftUI

struct RecommendationSectionView: View {
    let recommendations: [MooreMetricsRecommendation]
    let themeColor: Color
    var onSelected: ((String) -> Void)? = nil

    @State private var isVisible = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(recommendations) { rec in
                    RecommendationCard(rec: rec, themeColor: themeColor) {
                        onSelected?(rec.name)
                    }
                    .offset(x: isVisible ? 0 : 20)
                    .opacity(isVisible ? 1 : 0)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            withAnimation(AppTheme.Animation.easeInOut) {
                isVisible = true
            }
        }
    }
}

struct RecommendationCard: View {
    let rec: MooreMetricsRecommendation
    let themeColor: Color
    var action: (() -> Void)? = nil

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button {
            action?()
        } label: {
            cardContent
        }
        .buttonStyle(.interactive)
    }

    @ViewBuilder
    private var cardContent: some View {
        let accent = themeColor.highContrastAccent(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 0) {
            // Header: name + match badge
            HStack(alignment: .top) {
                Text(rec.name)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                Spacer()

                Text(String(format: "%.0f%%", rec.score * 100))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.12))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 6)

            // Reason / characteristics (2 lines)
            Text(rec.reason)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            // Bottom accent bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 3)
        }
        .padding(14)
        .frame(width: 220, height: 120)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
        .overlay(borderOverlay(accent: accent))
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
            .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
    }

    private func borderOverlay(accent: Color) -> some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [accent.opacity(0.2), Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.5
            )
    }
}
