import SwiftUI

struct InsightsSkeletonView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.section) {
                headerSkeleton
                heroGridSkeleton
                tasteProfileSkeleton
                castCrewSkeleton
            }
            .padding(.bottom, AppTheme.Spacing.section)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .shimmering()
    }

    private var headerSkeleton: some View {
        HStack {
            Text("Insights")
                .font(AppTheme.Font.display)
                .redacted(reason: .placeholder)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                Text("Cinephile Lab")
            }
            .font(AppTheme.Font.bodyBold)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
            )
            .redacted(reason: .placeholder)
        }
        .padding(.top, 24)
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
    }

    private var heroGridSkeleton: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 240, height: 86)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.7)
                        )
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
    }

    private var tasteProfileSkeleton: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: "Taste Profile", icon: "heart.circle.fill", iconColor: .pink)
                .redacted(reason: .placeholder)

            HStack(alignment: .center, spacing: AppTheme.Spacing.large) {
                DashboardCard {
                    HStack(spacing: AppTheme.Spacing.xLarge) {
                        Circle()
                            .stroke(Color.primary.opacity(0.06), lineWidth: 22)
                            .frame(width: 150, height: 150)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(0..<4, id: \.self) { _ in
                                HStack(spacing: AppTheme.Spacing.small) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(width: 12, height: 12)

                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(width: 60, height: 12)

                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.primary.opacity(0.04))
                                        .frame(width: 30, height: 12)
                                }
                            }
                        }
                    }
                }
                .frame(height: 198)

                VStack(spacing: AppTheme.Spacing.medium) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: AppTheme.Spacing.medium) {
                            Circle()
                                .fill(Color.primary.opacity(0.06))
                                .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 4) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 60, height: 8)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(width: 120, height: 12)
                            }

                            Spacer()

                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.06))
                                .frame(width: 50, height: 28)
                        }
                        .padding(12)
                        .background(Color.primary.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
                        )
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
        }
    }

    private var castCrewSkeleton: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: "Cast & Crew", icon: "person.3.fill", iconColor: .teal)
                .redacted(reason: .placeholder)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text("TOP RATED CAST")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                    .redacted(reason: .placeholder)
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<10, id: \.self) { _ in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 44, height: 64)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(width: 24, height: 10)
                                    
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(width: 80, height: 14)
                                }
                                
                                Spacer(minLength: 0)
                            }
                            .frame(width: 180, height: 64)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.primary.opacity(0.02))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.primary.opacity(0.04), lineWidth: 0.7)
                            )
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .padding(.vertical, 8)
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text("TOP RATED CREATORS")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                    .redacted(reason: .placeholder)
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<10, id: \.self) { _ in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 44, height: 64)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(width: 24, height: 10)
                                    
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(width: 80, height: 14)
                                }
                                
                                Spacer(minLength: 0)
                            }
                            .frame(width: 180, height: 64)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.primary.opacity(0.02))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.primary.opacity(0.04), lineWidth: 0.7)
                            )
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}
