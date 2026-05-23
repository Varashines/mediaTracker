import SwiftUI
import SwiftData

struct ReleaseCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme

    @Namespace private var calendarNamespace
    var viewModel: MediaViewModel
    
    @State private var calendarData: CalendarResult?
    @State private var selectedDate: Date? = Calendar.current.startOfDay(for: Date())
    @State private var currentDisplayMonth: Date = {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    }()
    @State private var isLoading = true
    
    var body: some View {
        HStack(spacing: 0) {
            // 1. LEFT PANE: The Contribution Graph
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 15) {
                        monthNavigation
                    }
                    .padding(.top, 30)
                    
                    if let data = calendarData {
                        contributionGraph(data: data)
                    } else if isLoading {
                        ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, 30)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: 320)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // 2. RIGHT PANE: Release Details
            ScrollView {
                VStack(alignment: .leading, spacing: 35) {
                    if let data = calendarData {
                        // NEW: WEEK FOCUS (Immediate temporal discovery)
                        weekFocusRow(data: data)
                        
                        Divider().padding(.vertical, 10)

                        if let date = selectedDate, let dayInfo = data.days[date] {
                            // Specific Day View
                            headerSection(date: date, count: dayInfo.items.count)
                            if dayInfo.items.isEmpty {
                                emptyDayView(date: date)
                            } else {
                                releasesList(items: dayInfo.items)
                            }
                        } else {
                            // All Month View
                            headerSection(date: currentDisplayMonth, count: data.allItems.count, isAllMonth: true)
                            if data.allItems.isEmpty {
                                emptyDayView(date: currentDisplayMonth, isAllMonth: true)
                            } else {
                                allMonthReleasesList(data: data)
                            }
                        }
                    }
                }
                .padding(.top, 30)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            refreshData(for: currentDisplayMonth)
        }
    }
    
    private var monthNavigation: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            let isSelected = selectedDate == nil
            
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedDate = nil
                }
            } label: {
                Text(currentDisplayMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
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
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
    
    private func changeMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: currentDisplayMonth) {
            let calendar = Calendar.current
            let newMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: newDate)) ?? newDate
            
            withAnimation(.easeInOut(duration: 0.3)) {
                currentDisplayMonth = newMonth
                selectedDate = nil // Reset to All Month view when navigating
            }
            refreshData(for: newMonth)
        }
    }
    
    private func refreshData(for month: Date) {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        
        // 1. Check Cache First
        if let cached = viewModel.calendarCache[startOfMonth] {
            self.calendarData = cached
            self.isLoading = false
            // Even if cached, we trigger background adjacent loads
            preloadAdjacentMonths(around: startOfMonth)
            return
        }

        isLoading = true
        
        // SAFETY TIMEOUT: Ensure loading indicator clears even if background task is slow/blocked
        Task {
            try? await Task.sleep(for: .seconds(6))
            await MainActor.run {
                if self.isLoading {
                    print("⚠️ Calendar: Loading took too long. Clearing spinner.")
                    self.isLoading = false
                }
            }
        }

        Task {
            let actor = CalendarFilterActor(modelContainer: modelContext.container)
            do {
                let result = try await actor.fetchCalendarData(for: startOfMonth)
                await MainActor.run {
                    viewModel.calendarCache[startOfMonth] = result
                    // RELIABILITY: Only update if the user hasn't moved to another month during fetch
                    if Calendar.current.isDate(currentDisplayMonth, inSameDayAs: startOfMonth) {
                        self.calendarData = result
                        self.isLoading = false
                    }
                    preloadAdjacentMonths(around: startOfMonth)
                }
            } catch {
                AppErrorState.shared.surfaceError("Failed to load calendar: \(error.localizedDescription)")
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
            guard viewModel.calendarCache[date] == nil else { continue }
            
            Task.detached(priority: .background) {
                let actor = CalendarFilterActor(modelContainer: container)
                if let result = try? await actor.fetchCalendarData(for: date) {
                    await MainActor.run {
                        viewModel.calendarCache[date] = result
                    }
                }
            }
        }
    }
    
    // MARK: - Graph Components
    
    @ViewBuilder
    private func contributionGraph(data: CalendarResult) -> some View {
        let calendar = Calendar.current
        let sortedDays = data.days.values.sorted { $0.date < $1.date }
        
        // Group by weeks for the GitHub look, but aligned to actual weekdays
        let weeks: [[CalendarDayInfo?]] = {
            var res: [[CalendarDayInfo?]] = []
            var currentWeek: [CalendarDayInfo?] = Array(repeating: nil, count: 7)
            
            for day in sortedDays {
                let weekday = calendar.component(.weekday, from: day.date) // 1 = Sunday, 7 = Saturday
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
        
        VStack(alignment: .leading, spacing: 15) {
            // Weekday labels
            HStack(spacing: 4) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 32)
                        .foregroundStyle(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(weeks.indices, id: \.self) { weekIdx in
                    HStack(spacing: 4) {
                        ForEach(0..<7) { dayIdx in
                            if let day = weeks[weekIdx][dayIdx] {
                                calendarCell(day: day)
                            } else {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.clear)
                                    .frame(width: 32, height: 32)
                            }
                        }
                    }
                }
            }
            
            // Legend
            HStack(spacing: 4) {
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5) { i in
                    let color: Color = {
                        if i == 0 {
                            return Color.secondary.opacity(0.1)
                        }
                        
                        let intensity = Double(i - 1) / 3.0 // Normalize 1-4 to 0-1
                        let o = Color.accentColor.oklch
                        if colorScheme == .dark {
                            // Light to Dark: L goes from 0.8 (Less) to 0.3 (More)
                            let l = 0.8 - (intensity * 0.5)
                            // Increase Chroma for "More" to keep it vibrant even when dark
                            let c = (o.c * 0.5) + (intensity * (o.c * 0.5))
                            return Color.fromOKLCH(l: l, c: c, h: o.h)
                        } else {
                            // Light to Dark: L goes from 0.95 (Less) to 0.4 (More)
                            let l = 0.95 - (intensity * 0.55)
                            let c = (o.c * 0.6) + (intensity * (o.c * 0.4))
                            return Color.fromOKLCH(l: l, c: c, h: o.h)
                        }
                    }()
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 10, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        }
    }
    
    @ViewBuilder
    private func weekFocusRow(data: CalendarResult) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let next7Days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        
        VStack(alignment: .leading, spacing: 15) {
            Text("NEXT 7 DAYS")
                .font(.system(size: 10, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(next7Days, id: \.self) { date in
                        let dayInfo = data.days[date]
                        let isSelected = selectedDate.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
                        let accent = Color.accentColor

                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) { selectedDate = date }
                        } label: {
                            VStack(spacing: 6) {
                                Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(isSelected ? accent : .secondary)
                                
                                Text(date.formatted(.dateTime.day()))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(isSelected ? accent : .primary)
                                
                                if let info = dayInfo, !info.items.isEmpty {
                                    Circle()
                                        .fill(isSelected ? accent : Color.accentColor.opacity(0.5))
                                        .frame(width: 4, height: 4)
                                }
                            }
                            .frame(width: 50, height: 72)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.primary.opacity(0.06))
                                        .matchedGeometryEffect(id: "selection_bg", in: calendarNamespace)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(accent.opacity(0.3), lineWidth: 0.8)
                                        }
                                } else {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.primary.opacity(0.03))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
    
    @ViewBuilder
    private func calendarCell(day: CalendarDayInfo) -> some View {
        let isSelected = selectedDate.map { Calendar.current.isDate(day.date, inSameDayAs: $0) } ?? false
        let isToday = Calendar.current.isDateInToday(day.date)
        
        let cellColor: Color = {
            if day.items.isEmpty {
                return Color.secondary.opacity(0.1)
            }
            
            let o = Color.accentColor.oklch
            if colorScheme == .dark {
                // Light to Dark: L goes from 0.8 (Less) to 0.3 (More)
                let l = 0.8 - (day.intensity * 0.5)
                let c = (o.c * 0.5) + (day.intensity * (o.c * 0.5))
                return Color.fromOKLCH(l: l, c: c, h: o.h)
            } else {
                // Light to Dark: L goes from 0.95 (Less) to 0.4 (More)
                let l = 0.95 - (day.intensity * 0.55)
                let c = (o.c * 0.6) + (day.intensity * (o.c * 0.4))
                return Color.fromOKLCH(l: l, c: c, h: o.h)
            }
        }()
        
        let vibrantAccent = Color.accentColor
        
        RoundedRectangle(cornerRadius: 4)
            .fill(cellColor)
            .frame(width: 32, height: 32)
            .overlay {
                if isToday {
                    Circle()
                        .fill(colorScheme == .dark ? Color.white : Color.black)
                        .frame(width: 4, height: 4)
                        .offset(y: 10)
                }
                if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(vibrantAccent, lineWidth: 2)
                        .padding(-2)
                }
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.3)) {
                    if isSelected {
                        selectedDate = nil
                    } else {
                        selectedDate = day.date
                    }
                }
            }
            .help("\(day.date.formatted(date: .abbreviated, time: .omitted)): \(day.items.count) releases")
    }
    
    // MARK: - Detail Components
    
    @ViewBuilder
    private func headerSection(date: Date, count: Int = 0, isAllMonth: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let accent = Color.accentColor.highContrastAccent(colorScheme: colorScheme)
            Text(isAllMonth ? "FULL MONTH OVERVIEW" : date.formatted(date: .complete, time: .omitted).uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .kerning(1.2)
            
            Text(isAllMonth ? date.formatted(.dateTime.month(.wide).year()) : "\(count) Releases")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
            
            if isAllMonth {
                Text("\(count) total releases this month")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func emptyDayView(date: Date, isAllMonth: Bool = false) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.minus")
                .font(.system(size: 50))
                .foregroundStyle(.secondary.opacity(0.3))
            
            Text(isAllMonth ? "No releases tracked for this month." : "No premieres or episodes tracked for this day.")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
    
    @ViewBuilder
    private func releasesList(items: [CalendarReleaseItem]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 160), spacing: 25)]
        
        LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
            ForEach(items) { item in
                releaseThumbnail(item: item)
            }
        }
    }
    
    @ViewBuilder
    private func allMonthReleasesList(data: CalendarResult) -> some View {
        let groupedByDay = Dictionary(grouping: data.allItems) { 
            Calendar.current.startOfDay(for: $0.date)
        }
        let sortedDays = groupedByDay.keys.sorted()
        
        VStack(alignment: .leading, spacing: 40) {
            ForEach(sortedDays, id: \.self) { day in
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text(day.formatted(.dateTime.day().month()))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Rectangle()
                            .fill(.secondary.opacity(0.2))
                            .frame(height: 1)
                    }
                    
                    releasesList(items: groupedByDay[day] ?? [])
                }
            }
        }
    }
    
    @ViewBuilder
    private func releaseThumbnail(item: CalendarReleaseItem) -> some View {
        let accent = Color.accentColor.highContrastAccent(colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 6) {
            MediaThumbnailView(metadata: item.metadata, mode: .grid)
            
            Text(item.releaseContext)
                .font(.system(size: 9.5, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(accent.opacity(0.12))
                .foregroundStyle(accent)
                .clipShape(Capsule())
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
