import SwiftUI
import SwiftData

/// "Year in Review" — a sidebar destination featuring a single-month heatmap navigator,
/// contextual Month Mode vs. Day Focus viewing, and a 2-row small poster layout.
struct YearReviewView: View {
    let modelContainer: ModelContainer
    var onSelectTitle: ((PersistentIdentifier) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var yearReviewNamespace

    @State private var review: YearInReview?
    @State private var isLoading = true
    @State private var displayedMonth: Date
    @State private var selectedDate: Date? = nil
    @State private var loadTask: Task<Void, Never>?
    @State private var showSharePreview = false

    private let cellSize: CGFloat = 32

    init(modelContainer: ModelContainer, onSelectTitle: ((PersistentIdentifier) -> Void)? = nil) {
        self.modelContainer = modelContainer
        self.onSelectTitle = onSelectTitle
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        _displayedMonth = State(initialValue: calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today)
        _selectedDate = State(initialValue: today)
    }

    var body: some View {
        Group {
            if isLoading && review == nil {
                skeleton
            } else if let review {
                HStack(spacing: 0) {
                    // 1. LEFT PANE: Month Navigation + Heatmap + 2026 Taste
                    calendarPane(review)
                        .frame(width: 320)
                        .background(.ultraThinMaterial.opacity(0.3))

                    Divider()

                    // 2. RIGHT PANE: Contextual Log (Month Overview OR Day Focus)
                    detailPane(review)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .id(review.year)
            } else {
                ContentUnavailableView("No Watch History", systemImage: "calendar", description: Text("No viewing data recorded for this year."))
            }
        }
        .background(AppTheme.Colors.background(for: colorScheme))
        .navigationTitle("Year in Review")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if review != nil {
                    Button {
                        withAnimation(AppTheme.Animation.springSnappy) {
                            showSharePreview = true
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .help("Share Year in Review (⌘S)")
                    .accessibilityLabel("Share Year in Review")
                }
            }
        }
        .sheet(isPresented: $showSharePreview) {
            if let review {
                shareSheet(review)
            }
        }
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

    // MARK: - Left Pane

    private func calendarPane(_ review: YearInReview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                monthNavigation
                    .padding(.top, AppTheme.Spacing.small)

                dayGrid(review)

                legend

                Divider()
                    .padding(.vertical, AppTheme.Spacing.micro)

                YearTasteCards(
                    genres: review.topGenres,
                    networks: review.topNetworks,
                    actors: review.topActors
                )
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.vertical, AppTheme.Spacing.medium)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var monthNavigation: some View {
        HStack(spacing: AppTheme.Spacing.tiny) {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(AppTheme.Font.caption)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            let isMonthMode = selectedDate == nil

            Button {
                withAnimation(AppTheme.Animation.springSnappy) {
                    selectedDate = nil
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(AppTheme.Font.caption2)
                    Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                        .font(AppTheme.Font.caption.weight(isMonthMode ? .bold : .medium))
                }
                .foregroundStyle(isMonthMode ? AppTheme.Colors.accent : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    if isMonthMode {
                        Capsule()
                            .fill(AppTheme.Colors.accent.opacity(0.14))
                            .overlay {
                                Capsule()
                                    .stroke(AppTheme.Colors.accent.opacity(0.35), lineWidth: 0.8)
                            }
                            .matchedGeometryEffect(id: "month_nav_active", in: yearReviewNamespace)
                    } else {
                        Capsule()
                            .fill(Color.primary.opacity(0.04))
                    }
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Click to view full month overview")

            Spacer()

            // Jump to Today button if not in current month
            let isCurrentMonth = Calendar.current.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
            if !isCurrentMonth {
                Button {
                    withAnimation(AppTheme.Animation.springSnappy) {
                        let calendar = Calendar.current
                        let today = calendar.startOfDay(for: Date())
                        displayedMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
                        selectedDate = today
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(AppTheme.Font.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Jump to current month & today")
            }

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(AppTheme.Font.caption)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func changeMonth(by value: Int) {
        withAnimation(AppTheme.Animation.springSnappy) {
            let calendar = Calendar.current
            if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
                displayedMonth = newMonth
                if let day = selectedDate, !calendar.isDate(day, equalTo: newMonth, toGranularity: .month) {
                    selectedDate = nil
                }
            }
        }
    }

    private func dayGrid(_ review: YearInReview) -> some View {
        let weeks = monthWeeks()
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(AppTheme.Font.small)
                        .foregroundStyle(.secondary)
                        .frame(width: cellSize)
                }
            }
            ForEach(0..<weeks.count, id: \.self) { weekIndex in
                HStack(spacing: 5) {
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
        let isSelected = selectedDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
        let isToday = Calendar.current.isDateInToday(date)

        return DayCellView(
            date: date,
            minutes: minutes,
            isSelected: isSelected,
            isToday: isToday,
            cellSize: cellSize,
            colorScheme: colorScheme,
            accent: AppTheme.Colors.accent
        ) {
            withAnimation(AppTheme.Animation.springSnappy) {
                if isSelected {
                    selectedDate = nil
                } else {
                    selectedDate = dayKey
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Text("Less")
                .font(AppTheme.Font.caption2)
                .foregroundStyle(.secondary)
            ForEach([0, 45, 90, 180, 300], id: \.self) { minutes in
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(DayCellView.cellFillColor(minutes: minutes, colorScheme: colorScheme, accent: AppTheme.Colors.accent))
                    .frame(width: 10, height: 10)
            }
            Text("More")
                .font(AppTheme.Font.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    // MARK: - Right Pane

    @ViewBuilder
    private func detailPane(_ review: YearInReview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
                if let selectedDate {
                    dayFocusSection(selectedDate, review: review)
                } else {
                    monthOverviewSection(review)
                }
            }
            .padding(AppTheme.Spacing.xLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - State 1: Month Overview Section

    private func monthOverviewSection(_ review: YearInReview) -> some View {
        let stats = review.monthStats(for: displayedMonth)
        let titles = review.monthTitles(for: displayedMonth)

        return VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            // Month Header
            VStack(alignment: .leading, spacing: 4) {
                Text("MONTH OVERVIEW")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(AppTheme.Colors.accent)
                    .kerning(AppTheme.Kerning.wide)

                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(AppTheme.Font.largeTitle)
            }

            // 3 Stat Glass Cards
            HStack(spacing: AppTheme.Spacing.medium) {
                statCard(
                    title: "MOVIES",
                    value: "\(stats.movies)",
                    subtitle: "Completed",
                    icon: "film"
                )

                statCard(
                    title: "TV EPISODES",
                    value: "\(stats.episodes)",
                    subtitle: "Watched",
                    icon: "tv"
                )

                statCard(
                    title: "WATCH TIME",
                    value: formatHoursAndMinutes(minutes: stats.minutes),
                    subtitle: "Total Duration",
                    icon: "clock"
                )
            }

            Divider()
                .padding(.vertical, AppTheme.Spacing.small)

            // Month Titles Tapestry
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                HStack(alignment: .firstTextBaseline) {
                    Text("TITLES WATCHED")
                        .font(AppTheme.Font.caption)
                        .kerning(AppTheme.Kerning.wide)
                        .foregroundStyle(.secondary)

                    Text("(\(titles.count))")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                }

                if titles.isEmpty {
                    ContentUnavailableView(
                        "Nothing Watched",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("No viewing activity recorded for \(displayedMonth.formatted(.dateTime.month(.wide).year())).")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    YearMonthCollageCard(month: displayedMonth, titles: titles, width: 560)
                        .environment(\.colorScheme, .dark)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.Colors.accent.opacity(0.25), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func statCard(title: String, value: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(AppTheme.Colors.accent)
                Text(title)
                    .font(AppTheme.Font.tiny)
                    .kerning(AppTheme.Kerning.wide)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(AppTheme.Font.title.weight(.bold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(AppTheme.Font.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(AppTheme.Colors.surfaceSubtle(for: colorScheme))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                }
        }
    }

    // MARK: - State 2: Day Focus Section (2-Row Small Poster Grid)

    private func dayFocusSection(_ day: Date, review: YearInReview) -> some View {
        let titles = review.titlesByDay[day] ?? []
        let activity = review.activityByDay[day] ?? .zero

        return VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            // Day Header
            VStack(alignment: .leading, spacing: 4) {
                Text("DAY FOCUS")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(AppTheme.Colors.accent)
                    .kerning(AppTheme.Kerning.wide)

                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.small) {
                    Text(day.formatted(.dateTime.weekday(.wide).day().month()))
                        .font(AppTheme.Font.largeTitle)

                    Text("• \(titles.count) title\(titles.count == 1 ? "" : "s")")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)

                    if activity.minutes > 0 {
                        Text("• \(formatHoursAndMinutes(minutes: activity.minutes))")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(AppTheme.Colors.accent)
                    }
                }
            }

            if titles.isEmpty {
                ContentUnavailableView(
                    "Nothing Logged",
                    systemImage: "moon.stars",
                    description: Text("No viewing activity logged for this date.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                // 2-Row Small Poster Grid
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Text("TITLES WATCHED")
                        .font(AppTheme.Font.caption2)
                        .kerning(AppTheme.Kerning.wide)
                        .foregroundStyle(.secondary)

                    let columns = [
                        GridItem(.adaptive(minimum: 80, maximum: 96), spacing: AppTheme.Spacing.medium)
                    ]

                    LazyVGrid(columns: columns, alignment: .leading, spacing: AppTheme.Spacing.medium) {
                        ForEach(titles) { title in
                            compactPosterCard(title)
                        }
                    }
                }
            }
        }
    }

    private func compactPosterCard(_ title: YearWatchedTitle) -> some View {
        Button {
            onSelectTitle?(title.id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 80, height: 120)

                    if let urlString = title.posterURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Color.secondary.opacity(0.1)
                        }
                        .frame(width: 80, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        Image(systemName: title.type == .movie ? "film" : "tv")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .frame(width: 80, height: 120)
                    }

                    // Taste Badge overlay
                    if title.tasteValue == "Loved" || title.tasteValue == "Love" {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Color.pink.opacity(0.85))
                            .clipShape(Circle())
                            .padding(4)
                    } else if title.tasteValue == "Liked" || title.tasteValue == "Like" {
                        Image(systemName: "hand.thumbsup.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Color.blue.opacity(0.85))
                            .clipShape(Circle())
                            .padding(4)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                }

                Text(title.title)
                    .font(AppTheme.Font.caption2.weight(.medium))
                    .lineLimit(1)
                    .frame(width: 80, alignment: .leading)
                    .foregroundStyle(.primary)

                Text(title.episodeCount > 0 ? "\(title.episodeCount) eps" : "Film")
                    .font(AppTheme.Font.tiny)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title.title)
    }

    private func formatHoursAndMinutes(minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMins = minutes % 60
        if hours == 0 {
            return "\(remainingMins)m"
        } else if remainingMins == 0 {
            return "\(hours)h"
        } else {
            return "\(hours)h \(remainingMins)m"
        }
    }

    private func shareSheet(_ review: YearInReview) -> some View {
        VStack(spacing: 20) {
            HStack {
                Text("\(review.year) Cinema Wrapped")
                    .font(AppTheme.Font.title2)
                Spacer()
                Button("Done") { showSharePreview = false }
                    .buttonStyle(.borderedProminent)
            }

            let monthTitles = review.monthTitles(for: displayedMonth)
            if !monthTitles.isEmpty {
                YearMonthCollageCard(month: displayedMonth, titles: monthTitles, width: 480)
                    .environment(\.colorScheme, .dark)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            } else {
                Text("No titles to export for this month.")
                    .font(AppTheme.Font.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppTheme.Spacing.xLarge)
        .frame(width: 540, height: 620)
    }

    private var skeleton: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Capsule().fill(AppTheme.Colors.surfaceSubtle(for: colorScheme)).frame(width: 160, height: 20)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 5), count: 7), spacing: 5) {
                    ForEach(0..<35, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 5).fill(AppTheme.Colors.surfaceGhost(for: colorScheme)).frame(width: 32, height: 32)
                    }
                }
            }
            .frame(width: 320)
            .padding(AppTheme.Spacing.xLarge)

            Divider()

            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                Capsule().fill(AppTheme.Colors.surfaceSubtle(for: colorScheme)).frame(width: 220, height: 24)
                HStack(spacing: 16) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8).fill(AppTheme.Colors.surfaceGhost(for: colorScheme)).frame(height: 80)
                    }
                }
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .fill(AppTheme.Colors.surfaceGhost(for: colorScheme))
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
            }
            .padding(AppTheme.Spacing.xLarge)
        }
        .shimmering()
    }
}

// MARK: - Day Cell with Interactive Hover

private struct DayCellView: View {
    let date: Date
    let minutes: Int
    let isSelected: Bool
    let isToday: Bool
    let cellSize: CGFloat
    let colorScheme: ColorScheme
    let accent: Color
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            RoundedRectangle(cornerRadius: 5.5)
                .fill(Self.cellFillColor(minutes: minutes, colorScheme: colorScheme, accent: accent))
                .frame(width: cellSize, height: cellSize)
                .scaleEffect(isHovered ? 1.12 : 1.0)
                .shadow(color: isHovered ? accent.opacity(0.3) : .clear, radius: 4, y: 1)
                .overlay {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(minutes > 0 ? Color.white.opacity(0.92) : Color.primary.opacity(0.6))
                        .offset(y: isToday ? -3 : 0)

                    if isToday {
                        Circle()
                            .fill(colorScheme == .dark ? Color.white : Color.black)
                            .frame(width: 3.5, height: 3.5)
                            .offset(y: 10)
                    }

                    if isSelected {
                        RoundedRectangle(cornerRadius: 5.5)
                            .stroke(accent, lineWidth: 2)
                            .padding(-1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onHover { isHovered = $0 }
        .help(tooltipText)
    }

    private var tooltipText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        if minutes > 0 {
            return "\(formatter.string(from: date)) · \(minutes) min"
        } else {
            return formatter.string(from: date)
        }
    }

    static func cellFillColor(minutes: Int, colorScheme: ColorScheme, accent: Color) -> Color {
        let level: Int
        switch minutes {
        case 0: level = 0
        case 1..<60: level = 1
        case 60..<120: level = 2
        case 120..<240: level = 3
        default: level = 4
        }

        guard level > 0 else {
            return Color.secondary.opacity(colorScheme == .dark ? 0.16 : 0.08)
        }

        let opacities: [Double] = [0, 0.35, 0.55, 0.78, 1.0]
        return accent.opacity(opacities[level])
    }
}
