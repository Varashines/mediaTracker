import SwiftUI

/// Month poster collage: a fixed 4×6 grid (24 cells). Shows up to 23 posters,
/// taste-sorted (Loved → Liked → Disliked → rest); the 24th cell is a "more"
/// indicator when there are more titles. Fills its container width.
struct YearMonthCollageCard: View {
    let month: Date
    let titles: [YearWatchedTitle]
    var width: CGFloat = 640

    private let columns = 4
    private let rows = 6
    private let gap: CGFloat = 6
    private let padding: CGFloat = 20

    private var sorted: [YearWatchedTitle] {
        let order: [String: Int] = ["Love": 0, "Like": 1, "Dislike": 2, "None": 3]
        return titles.sorted { (order[$0.tasteValue] ?? 4, $0.title) < (order[$1.tasteValue] ?? 4, $1.title) }
    }

    private var capacity: Int { columns * rows - 1 }

    private var counts: (loved: Int, liked: Int, disliked: Int) {
        titles.reduce((0, 0, 0)) { acc, t in
            switch t.tasteValue {
            case "Love": return (acc.0 + 1, acc.1, acc.2)
            case "Like": return (acc.0, acc.1 + 1, acc.2)
            case "Dislike": return (acc.0, acc.1, acc.2 + 1)
            default: return acc
            }
        }
    }

    var body: some View {
        let shown = Array(sorted.prefix(capacity))
        let hasMore = sorted.count > capacity
        let cellWidth = (width - padding * 2 - CGFloat(columns - 1) * gap) / CGFloat(columns)

        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<columns, id: \.self) { col in
                            let index = row * columns + col
                            if index < shown.count {
                                posterCell(shown[index], width: cellWidth)
                            } else if index == capacity && hasMore {
                                moreCell(width: cellWidth)
                            } else {
                                Color.clear.frame(width: cellWidth, height: cellWidth * 1.5)
                            }
                        }
                    }
                }
            }

            footer
        }
        .padding(padding)
        .frame(width: width, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(white: 0.13), Color(white: 0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("YOUR MONTH")
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .kerning(2)
                .foregroundStyle(AppTheme.Colors.accent)
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()).uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(.bottom, 14)
    }

    private func posterCell(_ title: YearWatchedTitle, width: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.07))
            if let url = title.posterURL, let url = URL(string: url) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.white.opacity(0.05)
                }
            } else {
                Image(systemName: "film")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .help(title.title)
    }

    private func moreCell(width: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.06))
            VStack(spacing: 4) {
                Text("+\(titles.count - capacity)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                Text("more")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            chip("\(counts.loved) LOVED", icon: "heart.fill", color: AppTheme.Colors.accent)
            chip("\(counts.liked) LIKED", icon: "hand.thumbsup.fill", color: .green)
            chip("\(counts.disliked) DISLIKED", icon: "hand.thumbsdown.fill", color: .red)
            Spacer()
            Text("MediaTracker \(String(Calendar.current.component(.year, from: month)))")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.top, 14)
    }

    private func chip(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.system(size: 8, weight: .black, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.15)))
    }
}
