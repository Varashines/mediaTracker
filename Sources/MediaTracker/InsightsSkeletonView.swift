import SwiftUI

struct InsightsSkeletonView: View {
    @State private var opacity: Double = 0.5

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.section) {
                headerSkeleton
                heroGridSkeleton
                tasteProfileSkeleton
                castCrewSkeleton
                recentlyWatchedSkeleton
            }
            .padding(.bottom, AppTheme.Spacing.section)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                opacity = 1.0
            }
        }
    }

    private var headerSkeleton: some View {
        HStack {
            Text("Insights")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .redacted(reason: .placeholder)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                Text("Cinephile Lab")
            }
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 0.5)
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
                Circle()
                    .stroke(Color.primary.opacity(0.06), lineWidth: 22)
                    .frame(width: 150, height: 150)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<4, id: \.self) { _ in
                        HStack(spacing: AppTheme.Spacing.small) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.06))
                                .frame(width: 12, height: 12)

                            Text("Love")
                                .font(AppTheme.Font.bodyBold)
                                .redacted(reason: .placeholder)
                                .frame(width: 60, alignment: .leading)

                            Text("0")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .redacted(reason: .placeholder)
                        }
                    }
                }
            }
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
                    .redacted(reason: .placeholder)
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<6, id: \.self) { _ in
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 44, height: 44)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 60, height: 10)
                            }
                            .frame(width: 80)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .padding(.vertical, 8)
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text("TOP RATED CREATORS")
                    .font(AppTheme.Font.caption)
                    .redacted(reason: .placeholder)
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<6, id: \.self) { _ in
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 44, height: 44)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 60, height: 10)
                            }
                            .frame(width: 80)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var recentlyWatchedSkeleton: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: "Recently Watched", icon: "play.circle.fill", iconColor: .blue)
                .redacted(reason: .placeholder)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.small) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 90, height: 135)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
        }
    }
}
