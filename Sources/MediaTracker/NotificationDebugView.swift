import SwiftUI
import UserNotifications
import SwiftData

struct NotificationDebugView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var notifications: [UNNotificationRequest] = []
    @State private var isLoading = true
    @State private var totalLibraryCount = 0
    @State private var upcomingFoundCount = 0
    @State private var upcomingSample: [(title: String, id: String)] = []
    @State private var rejectedSample: [(title: String, reason: String)] = []
    @State private var processingLog: [String] = []

    @State private var dbSchedule: [(title: String, date: Date, context: String)] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Button {
                            refresh()
                        } label: {
                            Label("Refresh Schedule", systemImage: "arrow.clockwise")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(dbSchedule.count) Items Found")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text("Database Records")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Controls")
                }
                
                Section {
                    if dbSchedule.isEmpty && !isLoading {
                        ContentUnavailableView("No Upcoming Releases", systemImage: "calendar.badge.minus")
                    } else {
                        ForEach(dbSchedule, id: \.title) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.headline)
                                    Text(item.context)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.blue)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Library Upcoming Schedule (Internal Data)")
                }

                Section {
                    if notifications.isEmpty && !isLoading {
                        Text("No System Alerts Registered").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(notifications, id: \.identifier) { request in
                            NotificationRequestRow(request: request)
                        }
                    }
                } header: {
                    Text("System Notification Queue (Diagnostic Only)")
                }
            }
            .navigationTitle("Upcoming Schedule")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                refresh()
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    private func refresh() {
        isLoading = true
        Task {
            let pending = await NotificationManager.shared.getPendingNotifications()
            
            // Database Schedule Analysis
            let manager = NotificationManager.shared
            let container = manager.modelContainer
            var schedule: [(title: String, date: Date, context: String)] = []
            
            if let container = container {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<MediaItem>()
                if let items = try? context.fetch(descriptor) {
                    let upcomingItems = items.filter { $0.isUpcoming }
                    
                    for item in upcomingItems {
                        let date = item.cachedNextAiringDate ?? item.releaseDate ?? .distantFuture
                        let info: String
                        if item.type == .movie {
                            info = "Movie Release"
                        } else if let tv = item.tvShowDetails {
                            let s = tv.nextSeasonNumber ?? 0
                            let e = tv.nextEpisodeNumber ?? 0
                            info = "Season \(s), Episode \(e)"
                        } else {
                            info = "Upcoming Release"
                        }
                        schedule.append((title: item.title, date: date, context: info))
                    }
                }
            }
            
            await MainActor.run {
                self.dbSchedule = schedule.sorted { $0.date < $1.date }
                self.notifications = pending.sorted { 
                    let date1 = ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantPast
                    let date2 = ($1.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantPast
                    return date1 < date2
                }
                self.isLoading = false
            }
        }
    }
}

struct NotificationRequestRow: View {
    let request: UNNotificationRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(request.content.title)
                    .font(.headline)
                Spacer()
                Text(request.identifier)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if !request.content.subtitle.isEmpty {
                Text(request.content.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(request.content.body)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Trigger", systemImage: "clock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                        Text(trigger.nextTriggerDate()?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown Date")
                            .font(.system(size: 11, design: .rounded))
                    } else if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger {
                        Text("In \(Int(trigger.timeInterval))s")
                            .font(.system(size: 11, design: .rounded))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("Metadata", systemImage: "info.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 8) {
                        let info = request.content.userInfo
                        if let type = info["ITEM_TYPE"] as? String {
                            BadgeLabel(text: type.uppercased(), color: .blue)
                        }
                        
                        if let s = info["SEASON_NUMBER"] as? Int, s > 0 {
                            BadgeLabel(text: "S\(s)", color: .orange)
                        }
                        
                        if let e = info["EPISODE_NUMBER"] as? Int, e > 0 {
                            BadgeLabel(text: "E\(e)", color: .green)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct BadgeLabel: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .kerning(0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
