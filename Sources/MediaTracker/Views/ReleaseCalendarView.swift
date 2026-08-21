import SwiftUI
import SwiftData

struct ReleaseCalendarView: View {
    private enum ReleaseFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case movies = "Movies"
        case shows = "TV Shows"

        var id: Self { self }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.sleepManager) private var sleepManager

    @Namespace private var calendarNamespace
    var viewModel: MediaViewModel
    var refreshID: Int = 0
    
    @State private var calendarData: CalendarResult?
    @State private var selectedDate: Date? = Calendar.current.startOfDay(for: Date())
    @State private var currentDisplayMonth: Date = {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    }()
    @State private var isLoading = true
    @State private var fetchTask: Task<Void, Never>? = nil
    @State private var releaseFilter: ReleaseFilter = .all
    
    var body: some View {
        Group {
            if isLoading && calendarData == nil {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
                        Capsule()
                            .fill(AppTheme.Colors.surfaceSubtle(for: colorScheme))
                            .frame(width: 200, height: 24)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.tiny), count: 7), spacing: AppTheme.Spacing.tiny) {
                            ForEach(0..<35, id: \.self) { _ in
                                Circle()
                                    .fill(AppTheme.Colors.surfaceGhost(for: colorScheme))
                                    .frame(height: 32)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.xLarge)
                    .frame(width: 320)
                    .adaptiveBackground()

                    Divider()

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                        Capsule()
                            .fill(AppTheme.Colors.surfaceSubtle(for: colorScheme))
                            .frame(width: 240, height: 20)
                        RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                            .fill(AppTheme.Colors.surfaceGhost(for: colorScheme))
                            .frame(height: 140)
                        RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                            .fill(AppTheme.Colors.surfaceGhost(for: colorScheme))
                            .frame(height: 140)
                    }
                    .padding(AppTheme.Spacing.xLarge)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .shimmering()
            } else {
                HStack(spacing: 0) {
                    // 1. LEFT PANE: The Contribution Graph
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                                monthNavigation
                            }
                            .padding(.top, AppTheme.Spacing.xLarge)

                            if let data = calendarData {
                                contributionGraph(data: data)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.xLarge)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: 320)
                    .adaptiveBackground()

                    Divider()

                    // 2. RIGHT PANE: Release Details
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
                            if let data = calendarData {
                                weekFocusRow(data: data)

                                Divider().padding(.vertical, AppTheme.Spacing.small)

                                if let date = selectedDate, let dayInfo = data.days[date] {
                                    let items = filtered(dayInfo.items)
                                    headerSection(date: date, count: items.count)
                                    if items.isEmpty {
                                        emptyDayView(date: date)
                                    } else {
                                        releasesList(items: items)
                                    }
                                } else {
                                    let items = filtered(data.allItems)
                                    headerSection(date: currentDisplayMonth, count: items.count, isAllMonth: true)
                                    if items.isEmpty {
                                        emptyDayView(date: currentDisplayMonth, isAllMonth: true)
                                    } else {
                                        allMonthReleasesList(items: items)
                                    }
                                }
                            }
                        }
                        .padding(.top, AppTheme.Spacing.large)
                        .padding(.horizontal, AppTheme.Spacing.xLarge)
                        .padding(.bottom, AppTheme.Spacing.xLarge)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .toolbarMaterial(isSleeping: sleepManager.isAsleep)
        .onAppear {
            refreshData(for: currentDisplayMonth)
        }
        .onChange(of: refreshID) { _, _ in
            refreshData(for: currentDisplayMonth)
        }
        .onDisappear {
            fetchTask?.cancel()
            fetchTask = nil
        }
        .background {
            Group {
                Button("") { changeMonth(by: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("") { changeMonth(by: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("") {
                    withAnimation(AppTheme.Animation.springSnappy) {
                        selectedDate = nil
                    }
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .opacity(0)
        }
    }
    
    private var monthNavigation: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(AppTheme.Font.caption)
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
            
            let isSelected = selectedDate == nil
            
            Button {
                withAnimation(AppTheme.Animation.springSnappy) {
                    selectedDate = nil
                }
            } label: {
                Text(currentDisplayMonth.formatted(.dateTime.month(.wide).year()))
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(isSelected ? AppTheme.Colors.accent : .secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                                .matchedGeometryEffect(id: "selection_bg", in: calendarNamespace)
                        } else {
                            Capsule()
                                .fill(Color.primary.opacity(0.03))
                        }
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Today button — jump back to current month
            let isCurrentMonth = Calendar.current.isDate(currentDisplayMonth, equalTo: Date(), toGranularity: .month)
            if !isCurrentMonth {
                Button {
                    withAnimation(AppTheme.Animation.springSnappy) {
                        let calendar = Calendar.current
                        currentDisplayMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
                        selectedDate = Date()
                    }
                    refreshData(for: currentDisplayMonth)
                } label: {
                    Label("Today", systemImage: "calendar")
                        .font(AppTheme.Font.caption)
                        .padding(.horizontal, AppTheme.Spacing.small)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Jump to current month")
            }
            
            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(AppTheme.Font.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Next month")
            .accessibilityLabel("Next month")
        }
    }
    
    private func changeMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: currentDisplayMonth) {
            let calendar = Calendar.current
            let newMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: newDate)) ?? newDate
            
            withAnimation(AppTheme.Animation.springSnappy) {
                currentDisplayMonth = newMonth
                selectedDate = nil
            }
            refreshData(for: newMonth)
        }
    }

    private func filtered(_ items: [CalendarReleaseItem]) -> [CalendarReleaseItem] {
        switch releaseFilter {
        case .all:
            items
        case .movies:
            items.filter { $0.metadata.type == .movie }
        case .shows:
            items.filter { $0.metadata.type == .tvShow }
        }
    }

    private var releaseFilterBar: some View {
        HStack(spacing: AppTheme.Spacing.micro) {
            ForEach(ReleaseFilter.allCases) { filter in
                let isSelected = releaseFilter == filter
                Button {
                    withAnimation(AppTheme.Animation.springSnappy) {
                        releaseFilter = filter
                    }
                } label: {
                    Text(filter.rawValue)
                        .font(AppTheme.Font.caption.weight(isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? AppTheme.Colors.accent : .secondary)
                        .padding(.horizontal, AppTheme.Spacing.small)
                        .padding(.vertical, AppTheme.Spacing.micro)
                        .background(
                            isSelected
                                ? AppTheme.Colors.accent.opacity(colorScheme == .dark ? 0.18 : 0.12)
                                : AppTheme.Colors.surfaceGhost(for: colorScheme),
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(AppTheme.Colors.surfaceSubtle(for: colorScheme), in: Capsule())
        .overlay {
            Capsule()
                .stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 0.5)
        }
    }

    private func refreshData(for month: Date) {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        
        // 1. Check Cache First
        if let cached = viewModel.display.calendarCache[startOfMonth] {
            self.calendarData = cached
            self.isLoading = false
            // Even if cached, we trigger background adjacent loads
            preloadAdjacentMonths(around: startOfMonth)
            return
        }

        isLoading = true
        
        // SAFETY TIMEOUT: Ensure loading indicator clears even if background task is slow/blocked
        // Track safety timeout task as part of the overall fetchTask parent context or internally
        
        fetchTask?.cancel()
        fetchTask = Task {
            let actor = CalendarFilterActor(modelContainer: modelContext.container)
            
            // Background safety timeout handler
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(6))
                if !Task.isCancelled {
                    await MainActor.run {
                        if self.isLoading {
                            AppLogger.warning("⚠️ Calendar: Loading took too long. Clearing spinner.", logger: AppLogger.ui)
                            self.isLoading = false
                        }
                    }
                }
            }
            
            do {
                let result = try await actor.fetchCalendarData(for: startOfMonth)
                timeoutTask.cancel()
                if Task.isCancelled { return }
                
                await MainActor.run {
                    viewModel.display.calendarCache[startOfMonth] = result
                    viewModel.display.trimCalendarCache(around: startOfMonth)
                    // RELIABILITY: Only update if the user hasn't moved to another month during fetch
                    if Calendar.current.isDate(currentDisplayMonth, inSameDayAs: startOfMonth) {
                        self.calendarData = result
                        self.isLoading = false
                    }
                    preloadAdjacentMonths(around: startOfMonth)
                }
            } catch {
                timeoutTask.cancel()
                if !(error is CancellationError) {
                    AppErrorState.shared.surfaceError("Failed to load calendar: \(error.localizedDescription)")
                }
                await MainActor.run { 
                    if Calendar.current.isDate(currentDisplayMonth, inSameDayAs: startOfMonth) {
                        self.isLoading = false 
                    }
                }
            }
        }
    }

    private func preloadAdjacentMonths(around month: Date) {
        let calendar = Calendar.current
        let adjacentDates = [
            calendar.date(byAdding: .month, value: -1, to: month),
            calendar.date(byAdding: .month, value: 1, to: month)
        ].compactMap { date -> Date? in
            guard let date = date else { return nil }
            return calendar.date(from: calendar.dateComponents([.year, .month], from: date))
        }

        let container = modelContext.container
        for date in adjacentDates {
            guard viewModel.display.calendarCache[date] == nil else { continue }
            
            Task.detached(priority: .background) {
                let actor = CalendarFilterActor(modelContainer: container)
                if let result = try? await actor.fetchCalendarData(for: date) {
                    await MainActor.run {
                        viewModel.display.calendarCache[date] = result
                    }
                }
            }
        }
        viewModel.display.trimCalendarCache(around: month)
    }
    
    // MARK: - Graph Components
    
    @ViewBuilder
    private func contributionGraph(data: CalendarResult) -> some View {
        let calendar = Calendar.current
        let sortedDays = data.days.values.sorted { $0.date < $1.date }
        
        let weeks: [[CalendarDayInfo?]] = {
            var res: [[CalendarDayInfo?]] = []
            var currentWeek: [CalendarDayInfo?] = Array(repeating: nil, count: 7)
            
            for day in sortedDays {
                let weekday = calendar.component(.weekday, from: day.date)
                currentWeek[weekday - 1] = day
                
                if weekday == 7 {
                    res.append(currentWeek)
                    currentWeek = Array(repeating: nil, count: 7)
                }
            }
            if currentWeek.contains(where: { $0 != nil }) {
                res.append(currentWeek)
            }
            return res
        }()
        
        let weekData: [(id: String, days: [CalendarDayInfo?])] = weeks.map { week in
            let firstDay = week.compactMap { $0 }.first?.date ?? Date()
            let id = ISO8601DateFormatter().string(from: firstDay)
            return (id, week)
        }
        
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 6) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(AppTheme.Font.small)
                        .frame(width: 38)
                        .foregroundStyle(.secondary)
                }
            }
            
            let accentOKLCH = AppTheme.Colors.accent.oklch
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(weekData, id: \.id) { week in
                    HStack(spacing: 6) {
                        ForEach(0..<7) { dayIdx in
                            if let day = week.days[dayIdx] {
                                calendarCell(day: day, oklch: accentOKLCH)
                            } else {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.clear)
                                    .frame(width: 38, height: 38)
                            }
                        }
                    }
                }
            }
            
            HStack(spacing: 4) {
                Text("Fewer releases").font(AppTheme.Font.caption2).foregroundStyle(.secondary)
                let legendColors = Self.legendColors(for: colorScheme)
                ForEach(0..<5) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(legendColors[i])
                        .frame(width: 10, height: 10)
                }
                Text("More releases").font(AppTheme.Font.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        }
        .id(currentDisplayMonth)
        .if(!AppThemeCoordinator.isReducingVisualEffects) {
            $0.transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .animation(AppTheme.Animation.easeInOut, value: currentDisplayMonth)
    }
    
    @ViewBuilder
    private func weekFocusRow(data: CalendarResult) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let isCurrentMonth = calendar.isDate(currentDisplayMonth, equalTo: today, toGranularity: .month)
        let anchor = isCurrentMonth ? today : currentDisplayMonth
        let focusDates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: anchor) }
        
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(isCurrentMonth
                     ? "NEXT 7 DAYS"
                     : "WEEK OF \(anchor.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(AppTheme.Font.caption2)
                    .kerning(AppTheme.Kerning.wide)
                    .foregroundStyle(.secondary)

                Spacer()
                releaseFilterBar
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.small) {
                    ForEach(focusDates, id: \.self) { date in
                        let dayInfo = data.days[date]
                        let isSelected = selectedDate.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
                        let accent = AppTheme.Colors.accent
                        let itemCount = filtered(dayInfo?.items ?? []).count

                        Button {
                            withAnimation(AppTheme.Animation.springSnappy) { selectedDate = date }
                        } label: {
                            VStack(spacing: 6) {
                                Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                                    .font(AppTheme.Font.small)
                                    .foregroundStyle(isSelected ? accent : .secondary)
                                
                                Text(date.formatted(.dateTime.day()))
                                    .font(AppTheme.Font.subtitle)
                                    .foregroundStyle(isSelected ? accent : .primary)
                                
                                // Count badge instead of dot
                                if itemCount > 0 {
                                    Text("\(itemCount)")
                                        .font(AppTheme.Font.tiny)
                                        .foregroundStyle(isSelected ? .white : accent)
                                        .frame(width: 16, height: 16)
                                        .background(isSelected ? accent : accent.opacity(0.15))
                                        .clipShape(Circle())
                                } else {
                                    Color.clear.frame(width: 16, height: 16)
                                }
                            }
                            .frame(width: 54, height: 84)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                                        .fill(Color.primary.opacity(0.06))
                                        .matchedGeometryEffect(id: "week_selection_bg", in: calendarNamespace)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                                                .stroke(accent.opacity(0.3), lineWidth: 0.8)
                                        }
                                } else {
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                                        .fill(Color.primary.opacity(0.03))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 1)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
    
    @ViewBuilder
    private func calendarCell(day: CalendarDayInfo, oklch: Color.OKLCH) -> some View {
        let isSelected = selectedDate.map { Calendar.current.isDate(day.date, inSameDayAs: $0) } ?? false
        let isToday = Calendar.current.isDateInToday(day.date)
        
        let cellColor: Color = {
            if day.items.isEmpty {
                return Color.secondary.opacity(0.1)
            }
            
            if colorScheme == .dark {
                let l = 0.8 - (day.intensity * 0.5)
                let c = (oklch.c * 0.5) + (day.intensity * (oklch.c * 0.5))
                return Color.fromOKLCH(l: l, c: c, h: oklch.h)
            } else {
                let l = 0.95 - (day.intensity * 0.55)
                let c = (oklch.c * 0.6) + (day.intensity * (oklch.c * 0.4))
                return Color.fromOKLCH(l: l, c: c, h: oklch.h)
            }
        }()
        
        let vibrantAccent = AppTheme.Colors.accent
        
        CalendarCellView(
            day: day, isSelected: isSelected, isToday: isToday,
            cellColor: cellColor, accent: vibrantAccent
        ) {
            withAnimation(AppTheme.Animation.springSnappy) {
                if isSelected {
                    selectedDate = nil
                } else {
                    selectedDate = day.date
                }
            }
        }
    }
    
    // MARK: - Detail Components
    
    @ViewBuilder
    private func headerSection(date: Date, count: Int = 0, isAllMonth: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
            let accent = AppTheme.Colors.accent.highContrastAccent(colorScheme: colorScheme)
            Text(isAllMonth ? "FULL MONTH OVERVIEW" : date.formatted(date: .complete, time: .omitted).uppercased())
                .font(AppTheme.Font.caption)
                .foregroundStyle(accent)
                .kerning(AppTheme.Kerning.wide)
            
            Text(isAllMonth ? date.formatted(.dateTime.month(.wide).year()) : "\(count) Releases")
                .font(AppTheme.Font.largeTitle)
            
            if isAllMonth {
                Text("\(count) total releases this month")
                    .font(AppTheme.Font.heading)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func emptyDayView(date: Date, isAllMonth: Bool = false) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.minus")
                .font(AppTheme.Font.heroTitle)
                .foregroundStyle(.secondary.opacity(0.3))
            
            Text(isAllMonth ? "No releases tracked for this month." : "No premieres or episodes tracked for this day.")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
    
    @ViewBuilder
    private func releasesList(items: [CalendarReleaseItem]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 160), spacing: AppTheme.Spacing.large)]
        
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            ForEach(items) { item in
                releaseThumbnail(item: item)
            }
        }
    }
    
    @ViewBuilder
    private func allMonthReleasesList(items: [CalendarReleaseItem]) -> some View {
        let groupedByDay = Dictionary(grouping: items) {
            Calendar.current.startOfDay(for: $0.date)
        }
        let sortedDays = groupedByDay.keys.sorted()
        
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            ForEach(sortedDays, id: \.self) { day in
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    HStack {
                        Text(day.formatted(.dateTime.day().month()))
                            .font(AppTheme.Font.subtitle)
                        Rectangle()
                            .fill(.secondary.opacity(0.2))
                            .frame(height: 1)
                    }
                    
                    releasesList(items: groupedByDay[day] ?? [])
                }
            }
        }
    }
    
    private static func legendColors(for colorScheme: ColorScheme) -> [Color] {
        let o = AppTheme.Colors.accent.oklch
        return (0..<5).map { i in
            if i == 0 { return Color.secondary.opacity(0.1) }
            let intensity = Double(i - 1) / 3.0
            if colorScheme == .dark {
                let l = 0.8 - (intensity * 0.5)
                let c = (o.c * 0.5) + (intensity * (o.c * 0.5))
                return Color.fromOKLCH(l: l, c: c, h: o.h)
            } else {
                let l = 0.95 - (intensity * 0.55)
                let c = (o.c * 0.6) + (intensity * (o.c * 0.4))
                return Color.fromOKLCH(l: l, c: c, h: o.h)
            }
        }
    }

    @ViewBuilder
    private func releaseThumbnail(item: CalendarReleaseItem) -> some View {
        let accent = AppTheme.Colors.accent.highContrastAccent(colorScheme: colorScheme)
        ReleaseThumbnailCard(item: item, accent: accent) {
            if let mediaItem = modelContext.model(for: item.metadata.id) as? MediaItem {
                viewModel.navigationPath.append(mediaItem)
            }
        }
    }
}

// MARK: - Release Thumbnail with Hover

private struct ReleaseThumbnailCard: View {
    let item: CalendarReleaseItem
    let accent: Color
    let action: (() -> Void)?
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MediaThumbnailView(metadata: item.metadata, mode: .grid, action: action)
            
            Text(item.releaseContext)
                .font(AppTheme.Font.small)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(accent.opacity(0.12))
                .foregroundStyle(accent)
                .clipShape(Capsule())
        }
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .shadow(color: isHovered ? accent.opacity(0.2) : .clear, radius: isHovered ? 8 : 0, y: isHovered ? 4 : 0)
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onHover { isHovered = $0 }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Calendar Cell with Hover

private struct CalendarCellView: View {
    let day: CalendarDayInfo
    let isSelected: Bool
    let isToday: Bool
    let cellColor: Color
    let accent: Color
    let onTap: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: onTap) {
            RoundedRectangle(cornerRadius: 5)
                .fill(cellColor)
                .frame(width: 38, height: 38)
                .scaleEffect(isHovered ? 1.12 : 1.0)
                .shadow(color: isHovered ? accent.opacity(0.3) : .clear, radius: isHovered ? 4 : 0, y: isHovered ? 2 : 0)
                .overlay {
                    Text(day.date.formatted(.dateTime.day()))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(day.intensity > 0.4 ? .white.opacity(0.9) : .primary.opacity(0.7))
                        .offset(y: isToday ? -4 : 0)
                    if isToday {
                        Circle()
                            .fill(colorScheme == .dark ? Color.white : Color.black)
                            .frame(width: 4, height: 4)
                            .offset(y: 13)
                    }
                    if isSelected {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(accent, lineWidth: 2)
                            .padding(-2)
                    }
                }
        }
        .buttonStyle(.plain)
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onHover { isHovered = $0 }
        .help("\(day.date.formatted(date: .abbreviated, time: .omitted)): \(day.items.count) releases")
    }
}
