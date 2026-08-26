import SwiftUI

struct InsightsSkeletonView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var fill: Color {
        AppTheme.Colors.surfaceSubtle(for: colorScheme)
    }

    private var label: Color {
        AppTheme.Colors.surfaceMuted(for: colorScheme)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.Spacing.xLarge) {
                // 0. Introduction Header
                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                    Capsule()
                        .fill(label)
                        .frame(width: 140, height: 12)
                    Capsule()
                        .fill(fill)
                        .frame(width: 280, height: 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.top, AppTheme.Spacing.xLarge)

                // 1. Cinema DNA Card
                skeletonCard(titleWidth: 100, secondLineWidth: 80) {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                        .fill(fill)
                        .frame(height: 72)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)

                // 2. Overview Card (4 Stat Pills)
                skeletonCard(titleWidth: 90, secondLineWidth: 110) {
                    HStack(spacing: AppTheme.Spacing.large) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                                .fill(fill)
                                .frame(height: 86)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .padding(.vertical, AppTheme.Spacing.medium)
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.top, AppTheme.Spacing.xLarge)

                // 3. Taste Profile Card (Split left/right)
                skeletonCard(titleWidth: 120, secondLineWidth: 90) {
                    HStack(spacing: AppTheme.Spacing.large) {
                        VStack(spacing: AppTheme.Spacing.small) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                                    .fill(fill)
                                    .frame(height: 38)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: AppTheme.Spacing.small) {
                            Circle()
                                .fill(fill)
                                .frame(width: 110, height: 110)
                            Capsule()
                                .fill(fill)
                                .frame(width: 120, height: 14)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.top, AppTheme.Spacing.xLarge)

                // 4. Hall of Fame (Cast)
                skeletonCard(titleWidth: 110, secondLineWidth: 50) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.large) {
                            ForEach(0..<5, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                                    .fill(fill)
                                    .frame(width: 180, height: 72)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.top, AppTheme.Spacing.xLarge)
            }
            .padding(.vertical, AppTheme.Spacing.xLarge)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .shimmering()
    }

    private func skeletonCard<Content: View>(titleWidth: CGFloat, secondLineWidth: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Capsule()
                    .fill(label)
                    .frame(width: titleWidth, height: 14)
                Capsule()
                    .fill(fill)
                    .frame(width: secondLineWidth, height: 14)
            }
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
            .padding(.top, AppTheme.Spacing.medium)
            .padding(.bottom, AppTheme.Spacing.small)

            content()
                .padding(.bottom, AppTheme.Spacing.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .insightsCardSurface()
    }
}
