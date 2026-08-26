import SwiftUI

// MARK: - Section Card (Cinema DNA signature style)

/// Accent-tinted card surface shared by all Insights section containers
/// (InsightsSectionCard, skeleton placeholders, SpectrumView).
struct InsightsCardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
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
}

extension View {
    func insightsCardSurface() -> some View {
        modifier(InsightsCardSurface())
    }
}

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
        .insightsCardSurface()
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
