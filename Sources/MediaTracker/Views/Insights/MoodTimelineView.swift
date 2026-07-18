import SwiftUI

struct MoodTimelineView: View {
    let stats: LibraryStats
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        InsightGlassTile {
            VStack(spacing: AppTheme.Spacing.small) {
                if !stats.moodBreakdown.isEmpty {
                    if let top = stats.moodBreakdown.max(by: { $0.percentage < $1.percentage }),
                       let topMood = Mood(rawValue: top.name) {
                        VStack(spacing: 4) {
                            HStack(spacing: 6) {
                                Text(topMood.emojiChar)
                                    .font(.system(size: 18))
                                Text(top.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                            Text("\(Int(top.percentage))% of tracked watches")
                                .font(AppTheme.Font.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    let remainingMoods = stats.moodBreakdown
                        .sorted { $0.percentage > $1.percentage }
                        .dropFirst()
                        .prefix(5)
                        .compactMap { Mood(rawValue: $0.name) }

                    if !remainingMoods.isEmpty {
                        VStack(spacing: 4) {
                            Text("Also felt")
                                .font(AppTheme.Font.tiny)
                                .foregroundStyle(.tertiary)
                            HStack(spacing: AppTheme.Spacing.compact) {
                                ForEach(remainingMoods, id: \.rawValue) { mood in
                                    Text(mood.emojiChar)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                    }

                    let total = stats.moodBreakdown.reduce(0) { $0 + $1.count }
                    Text("\(total) \(total == 1 ? "mood" : "moods") captured")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text("Tap ✦ Mood on any title to start your emotional map")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, AppTheme.Spacing.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, AppTheme.Spacing.small)
        }
    }
}
