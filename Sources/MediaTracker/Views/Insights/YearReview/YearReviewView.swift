import SwiftUI
import SwiftData

/// "Year in Review" — a sidebar destination mirroring the Release Calendar:
/// calendar heatmap on the left, contextual details on the right.
struct YearReviewView: View {
    let modelContainer: ModelContainer
    @Environment(\.colorScheme) private var colorScheme

    @State private var review: YearInReview?
    @State private var isLoading = true
    @State private var displayedMonth: Date
    @State private var selectedDay: Date?
    @State private var isMonthMode = false
    @State private var dayScrolled = false
    @State private var loadTask: Task<Void, Never>?

    private let cellSize: CGFloat = 26

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        _displayedMonth = State(initialValue: calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today)
        _selectedDay = State(initialValue: today)
    }

    var body: some View {
        Group {
            if isLoading && review == nil {
                skeleton
            } else if let review {
                HStack(spacing: 0) {
                    calendarPane(review)
                        .frame(width: 300)

                    Divider()

                    detailPane(review)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(AppTheme.Spacing.xLarge)
                }
                .id(review.year)
            } else {
                ContentUnavailableView("No watch history", systemImage: "calendar", description: Text("No viewing data recorded for this year."))
            }
        }
        .background(AppTheme.Colors.background(for: colorScheme))
        .navigationTitle("Year in Review")
        .onAppear(perform: load)
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func load() {
        guard review == nil else { return }
        loadTask?.cancel()
        isLoading = true
        loadTask = Task {
            let year = Calendar.current.component(.year, from: Date())
            let service = YearInReviewService(modelContainer: modelContainer)
            let result = await service.compute(year: year)
            if Task.isCancelled { return }
            await MainActor.run {
                self.review = result
                self.isLoading = false
            }
        }
    }

    // MARK: - Left pane

    private func calendarPane(_ review: YearInReview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                monthNavigation
                dayGrid(review)
                legend
            }
            .padding(AppTheme.Spacing.xLarge)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var monthNavigation: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(AppTheme.Font.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())

            Spacer()

            Button {
                withAnimation(AppTheme.Animation.springSnappy) {
                    isMonthMode = true
                    dayScrolled = false
                }
            } label: {
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(isMonthMode ? AppTheme.Colors.accent : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isMonthMode ? AppTheme.Colors.accent.opacity(0.12) : Color.clear)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
            .help("View this month's collage")

            Spacer()

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(AppTheme.Font.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
        }
    }

    private func changeMonth(by value: Int) {
        withAnimation(AppTheme.Animation.springSnappy) {
            let calendar = Calendar.current
            if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
                displayedMonth = newMonth
                dayScrolled = false
                if let day = selectedDay, !calendar.isDate(day, equalTo: newMonth, toGranularity: .month) {
                    selectedDay = nil
                    isMonthMode = true
                }
            }
        }
    }

    private func dayGrid(_ review: YearInReview) -> some View {
        let weeks = monthWeeks()
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(AppTheme.Font.small)
                        .foregroundStyle(.secondary)
                        .frame(width: cellSize)
                }
            }
            ForEach(0..<weeks.count, id: \.self) { weekIndex in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { dayIndex in
                        if let date = weeks[weekIndex][dayIndex] {
                            dayCell(date, review: review)
                        } else {
                            Color.clear.frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
    }

    private func monthWeeks() -> [[Date?]] {
        let calendar = Calendar.current
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        var weeks: [[Date?]] = []
        var current: [Date?] = Array(repeating: nil, count: 7)
        for day in 1...range.count {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: first) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            current[weekday - 1] = date
            if weekday == 7 {
                weeks.append(current)
                current = Array(repeating: nil, count: 7)
            }
        }
        if current.contains(where: { $0 != nil }) { weeks.append(current) }
        return weeks
    }

    private func dayCell(_ date: Date, review: YearInReview) -> some View {
        let dayKey = Calendar.current.startOfDay(for: date)
        let minutes = review.activityByDay[dayKey]?.minutes ?? 0
        let isSelected = selectedDay.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
        let isToday = Calendar.current.isDateInToday(date)

        return Button {
            withAnimation(AppTheme.Animation.springSnappy) {
                isMonthMode = false
                dayScrolled = false
                selectedDay = isSelected ? nil : dayKey
            }
        } label: {
            RoundedRectangle(cornerRadius: 5)
                .fill(cellColor(minutes))
                .frame(width: cellSize, height: cellSize)
                .overlay {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(minutes > 0 ? Color.white.opacity(0.9) : Color.primary.opacity(0.55))
                }
                .overlay {
                    if isToday {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(colorScheme == .dark ? Color.white : Color.black, lineWidth: 1)
                    }
                    if isSelected {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(AppTheme.Colors.accent, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(tooltip(for: dayKey, minutes: minutes))
    }

    private func cellColor(_ minutes: Int) -> Color {
        let level = intensityLevel(minutes)
        guard level > 0 else {
            return Color.secondary.opacity(colorScheme == .dark ? 0.18 : 0.1)
        }
        let opacities: [Double] = [0, 0.3, 0.5, 0.72, 1.0]
        return AppTheme.Colors.accent.opacity(opacities[level])
    }

    private func intensityLevel(_ minutes: Int) -> Int {
        switch minutes {
        case 0: return 0
        case 1..<60: return 1
        case 60..<120: return 2
        case 120..<240: return 3
        default: return 4
        }
    }

    private func tooltip(for day: Date, minutes: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        guard minutes > 0 else { return formatter.string(from: day) }
        return "\(formatter.string(from: day)) · \(minutes) min"
    }

    private var legend: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Text("Less")
                .font(AppTheme.Font.caption2)
                .foregroundStyle(.secondary)
            ForEach([0, 45, 90, 180, 300], id: \.self) { minutes in
                RoundedRectangle(cornerRadius: 2)
                    .fill(cellColor(minutes))
                    .frame(width: 11, height: 11)
            }
            Text("More")
                .font(AppTheme.Font.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Right pane

    @ViewBuilder
    private func detailPane(_ review: YearInReview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
                if isMonthMode {
                    monthCollageSection(review)
                } else if let selectedDay, let titles = review.titlesByDay[selectedDay], !titles.isEmpty {
                    daySection(selectedDay, titles)
                } else {
                    ContentUnavailableView("Pick a day", systemImage: "calendar.day.timeline.left", description: Text("Select a day on the calendar to see what you watched."))
                }

                Divider()

                YearTasteCards(genres: review.topGenres, networks: review.topNetworks, actors: review.topActors)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: Day detail — 2×2 posters + "+N" → horizontal scroll

    private func daySection(_ day: Date, _ titles: [YearWatchedTitle]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.formatted(.dateTime.weekday(.wide).day().month()))
                    .font(AppTheme.Font.largeTitle)
                Text("\(titles.count) title\(titles.count == 1 ? "" : "s")")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
            }

            if dayScrolled {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        ForEach(titles) { titleCard($0) }
                    }
                }
            } else {
                HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        ForEach(titles.prefix(4)) { titleCard($0) }
                    }
                    if titles.count > 4 {
                        Button {
                            withAnimation(AppTheme.Animation.springSnappy) { dayScrolled = true }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "chevron.right")
                                    .font(AppTheme.Font.caption)
                                Text("+\(titles.count - 4)")
                                    .font(AppTheme.Font.bodyBold)
                                Text("more")
                                    .font(AppTheme.Font.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 88, height: 132)
                            .background(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous).fill(AppTheme.Colors.accent.opacity(0.12)))
                            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous).stroke(AppTheme.Colors.accent.opacity(0.3), lineWidth: 0.5))
                            .foregroundStyle(AppTheme.Colors.accent)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .help("Show all titles")
                    }
                }
            }
        }
    }

    private func titleCard(_ title: YearWatchedTitle) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                if let url = title.posterURL, let url = URL(string: url) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "film").foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "film").foregroundStyle(.secondary)
                }
            }
            .frame(width: 88, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            Text(title.title)
                .font(AppTheme.Font.caption2)
                .lineLimit(1)
                .frame(width: 88, alignment: .leading)
            Text(title.episodeCount > 0 ? "\(title.episodeCount) eps" : "Film")
                .font(AppTheme.Font.small)
                .foregroundStyle(.secondary)
        }
        .frame(width: 88)
        .help(title.title)
    }

    // MARK: Month collage

    private var monthTitles: [YearWatchedTitle] {
        guard let review else { return [] }
        let calendar = Calendar.current
        var seen = Set<PersistentIdentifier>()
        return review.titlesByDay
            .filter { calendar.isDate($0.key, equalTo: displayedMonth, toGranularity: .month) }
            .values
            .flatMap { $0 }
            .filter { seen.insert($0.id).inserted }
    }

    private func monthCollageSection(_ review: YearInReview) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(displayedMonth.formatted(.dateTime.month(.wide))) in Review")
                    .font(AppTheme.Font.largeTitle)
                Text("\(monthTitles.count) titles")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
            }

            let titles = monthTitles
            if titles.isEmpty {
                ContentUnavailableView("Nothing watched", systemImage: "photo.on.rectangle.angled", description: Text("No viewing recorded for \(displayedMonth.formatted(.dateTime.month(.wide).year()))."))
            } else {
                YearMonthCollageCard(month: displayedMonth, titles: titles, width: collageWidth)
                    .environment(\.colorScheme, .dark)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.Colors.accent.opacity(0.25), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var collageWidth: CGFloat { 520 }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Capsule().fill(AppTheme.Colors.surfaceSubtle(for: colorScheme)).frame(width: 160, height: 20)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 4), count: 7), spacing: 4) {
                        ForEach(0..<35, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 5).fill(AppTheme.Colors.surfaceGhost(for: colorScheme)).frame(width: 26, height: 26)
                        }
                    }
                }
                .frame(width: 300)
                .padding(AppTheme.Spacing.xLarge)

                Divider()

                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Capsule().fill(AppTheme.Colors.surfaceSubtle(for: colorScheme)).frame(width: 200, height: 20)
                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                        .fill(AppTheme.Colors.surfaceGhost(for: colorScheme))
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                }
                .padding(AppTheme.Spacing.xLarge)
            }
        }
        .shimmering()
    }
}
