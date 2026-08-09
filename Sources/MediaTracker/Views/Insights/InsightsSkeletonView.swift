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
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                // Cinema DNA barcode skeleton
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(label)
                        .frame(width: 120, height: 16)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                        .fill(fill)
                        .frame(height: 64)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }

                // Overview — header + 3x2 stat pills
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(label)
                        .frame(width: 140, height: 16)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.large), count: 3),
                        spacing: AppTheme.Spacing.large
                    ) {
                        ForEach(0..<6, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                                .fill(fill)
                                .frame(height: 116)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }

                // Taste DNA — header + donut block
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(label)
                        .frame(width: 140, height: 16)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                        .fill(fill)
                        .frame(height: 200)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }

                // Ranked sections — generic adaptive rows
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(label)
                            .frame(width: 160, height: 16)
                            .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 16) {
                            ForEach(0..<6, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                                    .fill(fill)
                                    .frame(height: 90)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    }
                }
            }
            .padding(.vertical, AppTheme.Spacing.xLarge)
        }
        .scrollBounceBehavior(.basedOnSize)
        .shimmering()
    }
}
