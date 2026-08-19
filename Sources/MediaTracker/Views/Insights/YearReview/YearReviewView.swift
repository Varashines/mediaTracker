import SwiftUI
import SwiftData

// MARK: - Main View

struct YearReviewView: View {
    let modelContainer: ModelContainer
    var onSelectTitle: ((PersistentIdentifier) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var ns

    @State private var review: YearInReview?
    @State private var isLoading = true
    @State private var loadTask: Task<Void, Never>?

    // Calendar state
    @State private var selectedMonth: Date          // the month whose grid is showing
    @State private var selectedDay: Date? = nil     // nil = month-mode, set = day-mode

    init(modelContainer: ModelContainer, onSelectTitle: ((PersistentIdentifier) -> Void)? = nil) {
        self.modelContainer = modelContainer
        self.onSelectTitle = onSelectTitle
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        _selectedMonth = State(initialValue: cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today)
    }

    var body: some View {
        Group {
            if isLoading && review == nil {
                YearReviewSkeleton()
            } else if let review {
                mainContent(review)
            } else {
                ContentUnavailableView(
                    "No Watch History",
                    systemImage: "calendar",
                    description: Text("No viewing data recorded for \(String(Calendar.current.component(.year, from: Date()))).")
                )
            }
        }
        .background(AppTheme.Colors.background(for: colorScheme))
        .navigationTitle("Year in Review")
        .onAppear(perform: load)
        .onDisappear { loadTask?.cancel(); loadTask = nil }
    }

    // MARK: - Main Content

    private func mainContent(_ review: YearInReview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ── Hero ──────────────────────────────────────────────
                YearHeroSection(review: review, colorScheme: colorScheme)

                YearActivityOverview(
                    review: review,
                    selectedMonth: $selectedMonth,
                    selectedDay: $selectedDay,
                    colorScheme: colorScheme
                )
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.bottom, AppTheme.Spacing.large)

                Divider()
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .padding(.vertical, AppTheme.Spacing.large)

                // ── Two-pane: calendar left, overview right ───────────
                HStack(alignment: .center, spacing: 0) {
                    YearCalendarSection(
                        review: review,
                        selectedMonth: $selectedMonth,
                        selectedDay: $selectedDay,
                        colorScheme: colorScheme,
                        ns: ns
                    )
                    .frame(width: 360)

                    Divider()

                    YearContextPanel(
                        review: review,
                        selectedMonth: selectedMonth,
                        selectedDay: selectedDay,
                        colorScheme: colorScheme,
                        ns: ns,
                        onSelectTitle: onSelectTitle
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                // ── Year-wide taste section ───────────────────────────
                if !review.topGenres.isEmpty || !review.topNetworks.isEmpty || !review.topActors.isEmpty {
                    Divider()
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        .padding(.vertical, AppTheme.Spacing.large)

                    YearTasteSection(review: review, colorScheme: colorScheme)
                }

                Spacer().frame(height: AppTheme.Spacing.section)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Load

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
}

// MARK: - Hero Section

private struct YearHeroSection: View {
    let review: YearInReview
    let colorScheme: ColorScheme

    private var hoursWatched: Int { review.totalMinutes / 60 }
    private var busiestDayDescription: String {
        guard let busiestDay = review.busiestDay else { return "Build your watch history" }
        return "\(busiestDay.day.formatted(.dateTime.month(.abbreviated).day())) · \(formatTime(busiestDay.minutes))"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left: year + descriptor
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text(String(review.year))
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.accent)
                    .lineLimit(1)

                Text("Year in Review")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.85))

                Text("\(review.totalDaysWatched) active days · \(review.totalEpisodes) episodes watched")
                    .font(AppTheme.Font.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Right: stat tiles
            HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
                heroStat(
                    value: "\(review.totalSeries)",
                    label: "Series",
                    icon: "tv.fill"
                )
                heroStat(
                    value: "\(review.totalMovies)",
                    label: "Movies",
                    icon: "film.fill"
                )
                heroStat(
                    value: "\(hoursWatched)h",
                    label: "Watched",
                    icon: "clock.fill"
                )
            }
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
        .padding(.top, AppTheme.Spacing.xLarge)
        .padding(.bottom, AppTheme.Spacing.medium)

        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: "flame.fill")
                .foregroundStyle(AppTheme.Colors.accent)
            Text("Busiest day")
                .font(AppTheme.Font.caption)
                .foregroundStyle(.secondary)
            Text(busiestDayDescription)
                .font(AppTheme.Font.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.vertical, AppTheme.Spacing.micro)
        .background(AppTheme.Colors.surfaceSubtle(for: colorScheme), in: Capsule())
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
        .padding(.bottom, AppTheme.Spacing.large)
    }

    private func heroStat(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.accent.opacity(0.8))
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(minWidth: 70, alignment: .trailing)
    }
}

// MARK: - Year Activity Overview

private struct YearActivityOverview: View {
    let review: YearInReview
    @Binding var selectedMonth: Date
    @Binding var selectedDay: Date?
    let colorScheme: ColorScheme

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("YOUR VIEWING RHYTHM")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .kerning(1.2)
                        .foregroundStyle(AppTheme.Colors.accent)
                    Text("Select a month to explore its watch history")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(review.totalDaysWatched) days")
                    .font(AppTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92, maximum: 120), spacing: AppTheme.Spacing.small)],
                spacing: AppTheme.Spacing.small
            ) {
                ForEach(months, id: \.self) { month in
                    MonthActivityCard(
                        month: month,
                        review: review,
                        isSelected: calendar.isDate(selectedMonth, equalTo: month, toGranularity: .month),
                        isAvailable: month <= currentMonth,
                        colorScheme: colorScheme
                    ) {
                        withAnimation(AppTheme.Animation.springSnappy) {
                            selectedMonth = month
                            selectedDay = nil
                        }
                    }
                }
            }
        }
    }

    private var months: [Date] {
        guard let firstMonth = calendar.date(from: DateComponents(year: review.year, month: 1, day: 1)) else {
            return []
        }
        return (0..<12).compactMap { calendar.date(byAdding: .month, value: $0, to: firstMonth) }
    }

    private var currentMonth: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    }
}

private struct MonthActivityCard: View {
    let month: Date
    let review: YearInReview
    let isSelected: Bool
    let isAvailable: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.fixed(5), spacing: 2), count: 7)

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(month.formatted(.dateTime.month(.abbreviated)))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                    }
                }

                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(days, id: \.self) { date in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(
                                ReviewDayCell.fillColor(
                                    minutes: review.activityByDay[calendar.startOfDay(for: date)]?.minutes ?? 0,
                                    colorScheme: colorScheme,
                                    accent: AppTheme.Colors.accent
                                )
                            )
                            .frame(width: 5, height: 5)
                    }
                }
            }
            .foregroundStyle(isSelected ? AppTheme.Colors.accent : .secondary)
            .opacity(isAvailable ? 1 : 0.4)
            .padding(AppTheme.Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .fill(isSelected ? AppTheme.Colors.accent.opacity(colorScheme == .dark ? 0.18 : 0.10) : AppTheme.Colors.surfaceSubtle(for: colorScheme))
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .stroke(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: isSelected ? 1.5 : 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityLabel("\(month.formatted(.dateTime.month(.wide))) activity")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var days: [Date] {
        guard
            let range = calendar.range(of: .day, in: .month, for: month),
            let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: first) }
    }
}

// MARK: - Calendar Section

private struct YearCalendarSection: View {
    let review: YearInReview
    @Binding var selectedMonth: Date
    @Binding var selectedDay: Date?
    let colorScheme: ColorScheme
    let ns: Namespace.ID

    @State private var hoverDate: Date? = nil
    private let cellSize: CGFloat = 32
    private let cellSpacing: CGFloat = 6

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            monthNav
            if let selectedDay {
                selectedDaySummary(selectedDay)
            }
            dayGrid
            legend
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
        .padding(.vertical, AppTheme.Spacing.large)
    }

    private func selectedDaySummary(_ day: Date) -> some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: "calendar.circle.fill")
                .foregroundStyle(AppTheme.Colors.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Selected day")
                    .font(AppTheme.Font.caption2)
                    .foregroundStyle(.secondary)
                Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(AppTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Spacer()
            Button("Clear") {
                withAnimation(AppTheme.Animation.springSnappy) {
                    selectedDay = nil
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(AppTheme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                .fill(AppTheme.Colors.accent.opacity(colorScheme == .dark ? 0.14 : 0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                .stroke(AppTheme.Colors.accent.opacity(0.35), lineWidth: 0.5)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // Month navigation — arrows to shuffle across months
    private var monthNav: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Previous month")
            .accessibilityLabel("Previous month")

            Spacer()

            let isDaySelected = selectedDay != nil

            Button {
                withAnimation(AppTheme.Animation.springSnappy) {
                    selectedDay = nil
                }
            } label: {
                Text(monthLabel(selectedMonth))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(isDaySelected ? AppTheme.Colors.accent : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background {
                        Capsule().fill(isDaySelected
                            ? AppTheme.Colors.accent.opacity(colorScheme == .dark ? 0.18 : 0.12)
                            : Color.primary.opacity(0.06))
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Show \(monthLabel(selectedMonth)) overview")
            .accessibilityLabel("Show month overview")

            Spacer()

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selectedMonth >= calendar.startOfDay(for: calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!))
            .help("Next month")
            .accessibilityLabel("Next month")
        }
    }

    private func changeMonth(by value: Int) {
        withAnimation(AppTheme.Animation.springSnappy) {
            if let newMonth = calendar.date(byAdding: .month, value: value, to: selectedMonth) {
                guard newMonth <= Date() else { return }
                selectedMonth = newMonth
                if let day = selectedDay, !calendar.isDate(day, equalTo: newMonth, toGranularity: .month) {
                    selectedDay = nil
                }
            }
        }
    }

    private func monthLabel(_ month: Date) -> String {
        "\(month.formatted(.dateTime.month(.wide))), \(String(calendar.component(.year, from: month)))"
    }

    private var dayGrid: some View {
        let weeks = computeWeeks()
        return VStack(alignment: .leading, spacing: cellSpacing) {
            HStack(spacing: cellSpacing) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .frame(width: cellSize)
                }
            }

            ForEach(0..<weeks.count, id: \.self) { wi in
                HStack(spacing: cellSpacing) {
                    ForEach(0..<7, id: \.self) { di in
                        if let date = weeks[wi][di] {
                            let dayKey = calendar.startOfDay(for: date)
                            let minutes = review.activityByDay[dayKey]?.minutes ?? 0
                            let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                            let isToday = calendar.isDateInToday(date)
                            let isHovered = hoverDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false

                            ReviewDayCell(
                                date: date,
                                minutes: minutes,
                                isSelected: isSelected,
                                isToday: isToday,
                                isHovered: isHovered,
                                cellSize: cellSize,
                                colorScheme: colorScheme,
                                accent: AppTheme.Colors.accent
                            ) {
                                withAnimation(AppTheme.Animation.springSnappy) {
                                    selectedDay = isSelected ? nil : dayKey
                                }
                            } onHover: { hovering in
                                hoverDate = hovering ? date : nil
                            }
                        } else {
                            Color.clear.frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: AppTheme.Spacing.tiny) {
            Text("Less")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.7))
            ForEach([0, 45, 90, 180, 300], id: \.self) { mins in
                RoundedRectangle(cornerRadius: 2)
                    .fill(ReviewDayCell.fillColor(minutes: mins, colorScheme: colorScheme, accent: AppTheme.Colors.accent))
                    .frame(width: 9, height: 9)
            }
            Text("More")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(.top, 2)
    }

    private func computeWeeks() -> [[Date?]] {
        guard
            let first = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)),
            let range = calendar.range(of: .day, in: .month, for: first)
        else { return [] }

        var weeks: [[Date?]] = []
        var week: [Date?] = Array(repeating: nil, count: 7)
        for dayOffset in 0..<range.count {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: first) else { continue }
            let wd = calendar.component(.weekday, from: date) - 1   // 0=Sun
            week[wd] = date
            if wd == 6 {
                weeks.append(week)
                week = Array(repeating: nil, count: 7)
            }
        }
        if week.contains(where: { $0 != nil }) { weeks.append(week) }
        return weeks
    }
}

// MARK: - Day Cell

private struct ReviewDayCell: View {
    let date: Date
    let minutes: Int
    let isSelected: Bool
    let isToday: Bool
    let isHovered: Bool
    let cellSize: CGFloat
    let colorScheme: ColorScheme
    let accent: Color
    let onTap: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: cellSize * 0.16, style: .continuous)
                    .fill(
                        isSelected
                            ? accent.opacity(colorScheme == .dark ? 0.9 : 0.82)
                            : Self.fillColor(minutes: minutes, colorScheme: colorScheme, accent: accent)
                    )
                    .scaleEffect(isHovered || isSelected ? 1.12 : 1.0)

                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: cellSize * 0.3, weight: .medium))
                    .foregroundStyle(isSelected || minutes > 0 ? Color.white.opacity(0.95) : Color.primary.opacity(0.5))
                    .offset(y: isToday ? -cellSize * 0.11 : 0)

                if isToday {
                    Circle()
                        .fill(minutes > 0 ? Color.white : accent)
                        .frame(width: cellSize * 0.11, height: cellSize * 0.11)
                        .offset(y: cellSize * 0.3)
                }

                if isSelected {
                    RoundedRectangle(cornerRadius: cellSize * 0.16, style: .continuous)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.85) : Color.white, lineWidth: 1.5)
                        .padding(2)

                    Image(systemName: "checkmark")
                        .font(.system(size: cellSize * 0.22, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: cellSize * 0.38, height: cellSize * 0.38)
                        .background(accent, in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                        .offset(x: cellSize * 0.30, y: -cellSize * 0.30)
                }
            }
            .frame(width: cellSize, height: cellSize)
            .shadow(
                color: (isHovered || isSelected) && minutes > 0 ? accent.opacity(0.35) : .clear,
                radius: 5, y: 2
            )
        }
        .buttonStyle(.plain)
        .animation(AppTheme.Animation.microInteraction, value: isHovered)
        .animation(AppTheme.Animation.springSnappy, value: isSelected)
        .onHover { onHover($0) }
        .help(tooltip)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var tooltip: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        let base = f.string(from: date)
        guard minutes > 0 else { return base }
        let h = minutes / 60, m = minutes % 60
        let time = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        return "\(base) · \(time)"
    }

    private var accessibilityDescription: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        let activity = minutes > 0 ? ", \(tooltip.components(separatedBy: " · ").last ?? "") watched" : ", no watch activity"
        return "\(formatter.string(from: date))\(activity)"
    }

    static func fillColor(minutes: Int, colorScheme: ColorScheme, accent: Color) -> Color {
        switch minutes {
        case 0:        return Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05)
        case 1..<60:   return accent.opacity(0.3)
        case 60..<120: return accent.opacity(0.52)
        case 120..<240: return accent.opacity(0.74)
        default:       return accent
        }
    }
}

// MARK: - Context Panel (Month mode / Day mode)

private struct YearContextPanel: View {
    let review: YearInReview
    let selectedMonth: Date
    let selectedDay: Date?
    let colorScheme: ColorScheme
    let ns: Namespace.ID
    let onSelectTitle: ((PersistentIdentifier) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let day = selectedDay {
                DayDetailPanel(
                    day: day,
                    review: review,
                    colorScheme: colorScheme,
                    onSelectTitle: onSelectTitle
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
                .id("day_\(day)")
            } else {
                MonthDetailPanel(
                    month: selectedMonth,
                    review: review,
                    colorScheme: colorScheme,
                    onSelectTitle: onSelectTitle
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
                .id("month_\(selectedMonth)")
            }
        }
        .animation(AppTheme.Animation.springSnappy, value: selectedDay)
        .animation(AppTheme.Animation.springSnappy, value: selectedMonth)
    }
}

// MARK: - Month Detail Panel

private struct MonthDetailPanel: View {
    let month: Date
    let review: YearInReview
    let colorScheme: ColorScheme
    let onSelectTitle: ((PersistentIdentifier) -> Void)?

    @State private var scrolled = false

    private var stats: (movies: Int, series: Int, minutes: Int) {
        review.monthStats(for: month)
    }
    private var titles: [YearWatchedTitle] {
        review.monthTitles(for: month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MONTH OVERVIEW")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .kerning(1.2)
                        .foregroundStyle(AppTheme.Colors.accent)
                    Text("\(month.formatted(.dateTime.month(.wide))), \(String(Calendar.current.component(.year, from: month)))")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Text("\(titles.count) title\(titles.count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Stat row — series first
            HStack(spacing: AppTheme.Spacing.medium) {
                monthStatTile(value: "\(stats.series)", label: "Series", icon: "tv.fill")
                monthStatTile(value: "\(stats.movies)", label: "Movies", icon: "film.fill")
                monthStatTile(
                    value: formatTime(stats.minutes),
                    label: "Watch Time",
                    icon: "clock.fill"
                )
            }

            // Poster mosaic — bare posters, no captions
            if titles.isEmpty {
                emptyMonth
            } else {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Text("TITLES WATCHED (\(titles.count))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .kerning(1.0)
                        .foregroundStyle(.secondary)

                    if scrolled {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(titles) { title in
                                    PosterTile(title: title, onTap: { onSelectTitle?(title.id) }, width: 28)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    } else {
                        // Single row; a "+N" pill expands to horizontal scroll.
                        GeometryReader { geo in
                            let capacity = max(1, Int((geo.size.width + 6) / 40))
                            let shown = min(titles.count, capacity)
                            HStack(alignment: .top, spacing: 6) {
                                ForEach(titles.prefix(shown)) { title in
                                    PosterTile(title: title, onTap: { onSelectTitle?(title.id) }, width: 28)
                                }
                                if titles.count > shown {
                                    Button {
                                        withAnimation(AppTheme.Animation.springSnappy) { scrolled = true }
                                    } label: {
                                        VStack(spacing: 4) {
                                            Text("+\(titles.count - shown)")
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                            Text("more")
                                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }
                                        .foregroundStyle(AppTheme.Colors.accent)
                                        .frame(width: 42, height: 42)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(AppTheme.Colors.accent.opacity(0.12))
                                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(AppTheme.Colors.accent.opacity(0.3), lineWidth: 0.5))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Rectangle())
                                    .help("Show all titles")
                                }
                            }
                        }
                        .frame(height: 42)
                    }
                }
                .onChange(of: month) { _, _ in scrolled = false }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
        .padding(.vertical, AppTheme.Spacing.large)
    }

    private func monthStatTile(value: String, label: String, icon: String) -> some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.accent)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                        .fill(AppTheme.Colors.accent.opacity(colorScheme == .dark ? 0.12 : 0.08))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(AppTheme.Colors.surfaceSubtle(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private var emptyMonth: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.minus")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary.opacity(0.4))
                Text("Nothing watched in \(month.formatted(.dateTime.month(.wide)))")
                    .font(AppTheme.Font.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, AppTheme.Spacing.xLarge)
            Spacer()
        }
    }
}

// MARK: - Day Detail Panel

private struct DayDetailPanel: View {
    let day: Date
    let review: YearInReview
    let colorScheme: ColorScheme
    let onSelectTitle: ((PersistentIdentifier) -> Void)?

    @State private var scrolled = false

    private var titles: [YearWatchedTitle] {
        let key = Calendar.current.startOfDay(for: day)
        return review.titlesByDay[key] ?? []
    }
    private var activity: YearDayActivity {
        let key = Calendar.current.startOfDay(for: day)
        return review.activityByDay[key] ?? .zero
    }
    private var seriesCount: Int {
        titles.filter { $0.type == .tvShow }.count
    }
    private var movieCount: Int {
        titles.filter { $0.type == .movie }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DAY OVERVIEW")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .kerning(1.2)
                        .foregroundStyle(AppTheme.Colors.accent)
                    Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer()
                if activity.minutes > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatTime(activity.minutes))
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.accent)
                        Text("Watch Time")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Series / Movies overview
            if !titles.isEmpty {
                HStack(spacing: AppTheme.Spacing.medium) {
                    dayStatTile(value: "\(seriesCount)", label: "Series")
                    dayStatTile(value: "\(movieCount)", label: "Movies")
                }
            }

            if titles.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "moon.stars")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary.opacity(0.4))
                        Text("Nothing logged for this day")
                            .font(AppTheme.Font.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, AppTheme.Spacing.xLarge)
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Text("WATCHED (\(titles.count))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .kerning(1.0)
                        .foregroundStyle(.secondary)

                    // Single row of posters; "+N more" pill if it exceeds the row
                    if scrolled {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(titles) { title in
                                    PosterTile(title: title, onTap: { onSelectTitle?(title.id) }, width: 56)
                                }
                            }
                            .padding(.vertical, 10)
                        }
                    } else {
                        GeometryReader { geo in
                            let capacity = max(1, Int((geo.size.width + 6) / 62))
                            let shown = min(titles.count, capacity)
                            HStack(alignment: .top, spacing: 6) {
                                ForEach(titles.prefix(shown)) { title in
                                    PosterTile(title: title, onTap: { onSelectTitle?(title.id) }, width: 56)
                                }
                                if titles.count > shown {
                                    Button {
                                        withAnimation(AppTheme.Animation.springSnappy) { scrolled = true }
                                    } label: {
                                        VStack(spacing: 4) {
                                            Text("+\(titles.count - shown)")
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                            Text("more")
                                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }
                                        .foregroundStyle(AppTheme.Colors.accent)
                                        .frame(width: 56, height: 84)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(AppTheme.Colors.accent.opacity(0.12))
                                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(AppTheme.Colors.accent.opacity(0.3), lineWidth: 0.5))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Rectangle())
                                    .help("Show all titles")
                                }
                            }
                        }
                        .frame(height: 84)
                    }
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
        .padding(.vertical, AppTheme.Spacing.large)
        .onChange(of: day) { _, _ in scrolled = false }
    }

    private func dayStatTile(value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .kerning(0.8)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(AppTheme.Colors.surfaceSubtle(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Poster Tile (heatmap-cell sized, bare — no captions)

private struct PosterTile: View {
    let title: YearWatchedTitle
    let onTap: () -> Void
    var width: CGFloat = 28
    @State private var isHovered = false

    private var h: CGFloat { width * 1.5 }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: width, height: h)

                if let urlStr = title.posterURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                                .frame(width: width, height: h)
                                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                        default:
                            fallbackIcon
                        }
                    }
                } else {
                    fallbackIcon
                }

                tasteBadge
            }
            .frame(width: width, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .scaleEffect(isHovered ? 1.25 : 1.0)
            .shadow(
                color: isHovered ? .black.opacity(0.25) : .clear,
                radius: 6, y: 3
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onHover { isHovered = $0 }
        .help(title.title)
    }

    private var fallbackIcon: some View {
        Image(systemName: title.type == .movie ? "film" : "tv")
            .font(.system(size: 8, weight: .regular))
            .foregroundStyle(Color.primary.opacity(0.3))
            .frame(width: width, height: h)
    }

    @ViewBuilder
    private var tasteBadge: some View {
        switch title.tasteValue {
        case "Loved", "Love":
            badge("heart.fill", color: .pink)
        case "Liked", "Like":
            badge("hand.thumbsup.fill", color: .blue)
        default:
            EmptyView()
        }
    }

    private func badge(_ icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 4.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(2)
            .background(color.opacity(0.9), in: Circle())
            .padding(2)
    }
}

// MARK: - Year Taste Section

private struct YearTasteSection: View {
    let review: YearInReview
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            Text("YOUR \(String(review.year)) TASTE")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .kerning(1.2)
                .foregroundStyle(AppTheme.Colors.accent)
                .padding(.horizontal, AppTheme.Spacing.pageMargin)

            if !review.topGenres.isEmpty {
                tasteRow(title: "Top Genres") {
                    ForEach(review.topGenres.prefix(6), id: \.name) { genre in
                        DiscoveryCard(
                            node: DiscoveryNode(name: genre.name, logoPath: nil, count: genre.count),
                            style: .text,
                            baseColor: .indigo,
                            badgeValue: "\(Int(genre.score * 100))%"
                        ) {}
                        .frame(width: 170, height: 60)
                    }
                }
            }

            if !review.topNetworks.isEmpty {
                tasteRow(title: "Networks You Binged") {
                    ForEach(review.topNetworks.prefix(6), id: \.name) { network in
                        DiscoveryCard(
                            node: DiscoveryNode(name: network.name, logoPath: network.logoPath, count: network.count),
                            style: .logo
                        ) {}
                        .frame(width: 170, height: 90)
                    }
                }
            }

            if !review.topLanguages.isEmpty {
                tasteRow(title: "Languages You Loved") {
                    ForEach(review.topLanguages.prefix(6), id: \.name) { language in
                        DiscoveryCard(
                            node: DiscoveryNode(name: language.name, logoPath: nil, count: language.count),
                            style: .text,
                            baseColor: .teal,
                            badgeValue: "\(Int(language.score * 100))%"
                        ) {}
                        .frame(width: 170, height: 60)
                    }
                }
            }

            if !review.topActors.isEmpty {
                tasteRow(title: "Actors of Your Year") {
                    ForEach(Array(review.topActors.prefix(6).enumerated()), id: \.element.id) { index, actor in
                        PersonRankCard(
                            rank: index + 1,
                            name: actor.name,
                            score: actor.score,
                            profileURL: actor.profileURL,
                            accentColor: AppTheme.Colors.accent,
                            style: .cast
                        )
                    }
                }
            }
        }
        .padding(.bottom, AppTheme.Spacing.large)
    }

    private func tasteRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .kerning(1.0)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppTheme.Spacing.pageMargin)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.small) {
                    content()
                }
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.vertical, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - Skeleton

private struct YearReviewSkeleton: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            HStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)).frame(width: 130, height: 70)
                Spacer()
                HStack(spacing: 16) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)).frame(width: 70, height: 56)
                    }
                }
            }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    Capsule().fill(Color.primary.opacity(0.07)).frame(width: 120, height: 22)
                    VStack(spacing: 4) {
                        ForEach(0..<5, id: \.self) { _ in
                            HStack(spacing: 4) {
                                ForEach(0..<7, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)).frame(width: 28, height: 28)
                                }
                            }
                        }
                    }
                }
                .frame(width: 280)
                .padding(.trailing, AppTheme.Spacing.large)

                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)).frame(width: 200, height: 24)
                    HStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)).frame(width: 120, height: 72)
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(0..<8, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)).frame(width: 28, height: 42)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
        .padding(.vertical, AppTheme.Spacing.xLarge)
        .shimmering()
    }
}

// MARK: - Shared helpers

private func formatTime(_ minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    if h == 0 { return "\(m)m" }
    if m == 0 { return "\(h)h" }
    return "\(h)h \(m)m"
}
