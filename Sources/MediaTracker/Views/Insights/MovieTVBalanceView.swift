import SwiftUI

struct MovieTVBalanceView: View {
    let movieMinutes: Int
    let tvMinutes: Int
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let total = movieMinutes + tvMinutes
        let moviePct = total > 0 ? Double(movieMinutes) / Double(total) : 0
        let tvPct = total > 0 ? Double(tvMinutes) / Double(total) : 0

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Movie & TV Balance")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .kerning(1.0)
                Spacer()
                if total > 0 {
                    HStack(spacing: 12) {
                        Label("Movies", systemImage: "film.fill")
                            .font(AppTheme.Font.caption2)
                            .foregroundStyle(.blue)
                        Label("TV", systemImage: "tv.fill")
                            .font(AppTheme.Font.caption2)
                            .foregroundStyle(.purple)
                    }
                }
            }

            if total == 0 {
                CuteEmptyState(icon: "popcorn", message: "Start watching to see your balance", color: .orange)
                    .frame(height: 40)
            } else {
                GeometryReader { geo in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.blue.gradient)
                            .frame(width: geo.size.width * CGFloat(moviePct))
                        if tvPct > 0 {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.purple.gradient)
                                .frame(width: geo.size.width * CGFloat(tvPct))
                        }
                    }
                }
                .frame(height: 20)

                HStack {
                    Text("\(String(format: "%.0f", moviePct * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                    Spacer()
                    Text(balanceMessage(moviePct: moviePct, tvPct: tvPct))
                        .font(AppTheme.Font.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(String(format: "%.0f", tvPct * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.purple)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
    }

    private func balanceMessage(moviePct: Double, tvPct: Double) -> String {
        if tvPct > 0.75 { return "You're basically a TV channel 📡" }
        if moviePct > 0.75 { return "Certified cinephile 🎬" }
        if abs(moviePct - tvPct) < 0.1 { return "Perfectly balanced ⚖️" }
        return "Well rounded ✨"
    }
}
