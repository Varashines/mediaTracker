import SwiftUI

struct StreakVelocityView: View {
    let currentStreak: Int
    let longestStreak: Int
    let velocity: Int
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            // Streak card
            InsightGlassTile {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(.orange.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Text("🔥")
                            .font(.system(size: 20))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(currentStreak) day streak")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        if currentStreak > 0 {
                            Text("Longest: \(longestStreak) days")
                                .font(AppTheme.Font.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Start a streak today!")
                                .font(AppTheme.Font.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)

            // Velocity card
            InsightGlassTile {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(.teal.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.teal)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("~\(velocity) min/day")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("Last 30 days")
                            .font(AppTheme.Font.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
    }
}
