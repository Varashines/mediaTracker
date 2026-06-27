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
