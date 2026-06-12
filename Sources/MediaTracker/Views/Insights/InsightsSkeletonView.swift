import SwiftUI

struct InsightsSkeletonView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.section) {
                // Passport header skeleton
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 100)
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                // Hero + Taste DNA skeleton (side by side)
                HStack(alignment: .top, spacing: AppTheme.Spacing.large) {
                    // Hero 2x2 grid
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 100, height: 16)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(height: 82)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Taste DNA
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 100, height: 16)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 192)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)

                // Genres skeleton — adaptive grid
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 140, height: 16)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 16) {
                        ForEach(0..<6, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 60)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }

                // Barcode skeleton
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 120, height: 16)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 60)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }

                // Studios & Networks skeleton — merged grid
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 180, height: 16)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 16) {
                        ForEach(0..<6, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 60)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }

                // Languages skeleton — separate grid
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 120, height: 16)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 16) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 60)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }

                // Cast skeleton — horizontal scroll
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 140, height: 16)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<6, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 140, height: 90)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        .padding(.vertical, 4)
                    }
                }

                // Crew skeleton — horizontal scroll
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 140, height: 16)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<6, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 140, height: 90)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        .padding(.vertical, 4)
                    }
                }

                // Streak skeleton
                HStack(spacing: AppTheme.Spacing.medium) {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 70)
                    RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 70)
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
            }
            .padding(.vertical, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .shimmering()
    }
}
