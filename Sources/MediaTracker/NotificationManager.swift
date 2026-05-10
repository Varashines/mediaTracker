import Foundation
import SwiftData
@preconcurrency import UserNotifications

@MainActor
class NotificationManager: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    var modelContainer: ModelContainer?
    
    override init() {
        super.init()
    }

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }
    
    private var isProperlyBundled: Bool {
        return Bundle.main.bundleIdentifier != nil && !Bundle.main.bundlePath.hasSuffix(".xctest")
    }

    func requestPermission() {
        guard isProperlyBundled else {
            print("⚠️ Skipping notification permission request: App is not running from a proper .app bundle.")
            return
        }
        
        Task {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            
            // Register Categories and Actions
            let markWatchedAction = UNNotificationAction(identifier: "MARK_WATCHED_ACTION", title: "Mark as Watched", options: [])
            
            let movieCategory = UNNotificationCategory(identifier: "MOVIE_RELEASE", actions: [markWatchedAction], intentIdentifiers: [], options: [])
            let tvCategory = UNNotificationCategory(identifier: "TV_EPISODE_RELEASE", actions: [markWatchedAction], intentIdentifiers: [], options: [])
            
            center.setNotificationCategories([movieCategory, tvCategory])

            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                if granted {
                    print("✅ Notification permission granted.")
                }
            } catch {
                print("❌ Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    func scheduleMovieNotification(id: String, title: String, releaseDate: Date?, posterURL: String?) async {
        guard isProperlyBundled else { return }
        guard let releaseDate = releaseDate, releaseDate > Date() else { 
            print("ℹ️ Skipping notification for \(title): Release date is in the past or nil.")
            return 
        }
        
        print("🔔 Scheduling notification for movie: \(title) (\(releaseDate))")
        let identifier = "movie-\(id)"
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = "Movie Release"
        content.body = "Is out today! Enjoy the premiere. 🍿"
        content.sound = .default
        content.categoryIdentifier = "MOVIE_RELEASE"
        content.userInfo = ["ITEM_ID": id, "ITEM_TYPE": "movie"]
        if let posterURL = posterURL, let attachment = try? await downloadImage(from: posterURL) {
            content.attachments = [attachment]
        }
        await finalizeSchedule(identifier: identifier, content: content, date: releaseDate)
    }
    
    func scheduleTVNotification(id: String, title: String, posterURL: String?, nextDate: Date?, nextEpisodeNumber: Int?, nextSeasonNumber: Int?, nextEpisodeTime: String?) async {
        guard isProperlyBundled else { return }
        guard let nextDate = nextDate, nextDate > Date() else { 
            print("ℹ️ Skipping notification for \(title): Next air date is in the past or nil.")
            return 
        }
        
        print("🔔 Scheduling notification for TV show: \(title) (\(nextDate))")
        let identifier = "tv-\(id)"
        let content = UNMutableNotificationContent()
        content.title = title
        content.categoryIdentifier = "TV_EPISODE_RELEASE"
        
        let season = nextSeasonNumber ?? 0
        let episode = nextEpisodeNumber ?? 0
        
        content.userInfo = [
            "ITEM_ID": id, 
            "ITEM_TYPE": "tvShow",
            "SEASON_NUMBER": season,
            "EPISODE_NUMBER": episode
        ]
        
        if episode == 1 {
            content.subtitle = "Season Premiere"
            content.body = "Season \(season) starts today! 📺"
        } else {
            content.subtitle = "New Episode"
            content.body = "Season \(season), Episode \(episode) is available now."
        }
        content.sound = .default
        
        if let posterURL = posterURL, let attachment = try? await downloadImage(from: posterURL) {
            content.attachments = [attachment]
        }
        await finalizeSchedule(identifier: identifier, content: content, date: nextDate, time: nextEpisodeTime)
    }
    
    private func finalizeSchedule(identifier: String, content: UNMutableNotificationContent, date: Date, time: String? = nil) async {
        guard isProperlyBundled else { return }
        let center = UNUserNotificationCenter.current()
        
        // Ensure we use the user's current calendar to respect their local timezone (e.g., IST)
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        
        // 1. If a specific time string is provided (e.g., "20:00") and the date is at 00:00, use the time string.
        if let time = time, dateComponents.hour == 0 && dateComponents.minute == 0 {
            let timeParts = time.split(separator: ":")
            if timeParts.count >= 2, let h = Int(timeParts[0]), let m = Int(timeParts[1]) {
                dateComponents.hour = h
                dateComponents.minute = m
            }
        }
        
        // 2. Default fallback: If it's still 00:00 local time, it's likely a date-only object from a generic release.
        if dateComponents.hour == 0 && dateComponents.minute == 0 {
            dateComponents.hour = 9
            dateComponents.minute = 0
        }
        
        let trigger1 = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        
        // Phase 6 Critical Fix: Clone the attachment BEFORE handing request1 to the system.
        // The OS takes ownership of the file and moves it when `center.add` is called.
        var day2Attachments: [UNNotificationAttachment] = []
        if let firstAttachment = content.attachments.first {
            let originalURL = firstAttachment.url
            let tmpDir = FileManager.default.temporaryDirectory
            let clonedURL = tmpDir.appendingPathComponent(UUID().uuidString + ".jpg")
            do {
                if FileManager.default.fileExists(atPath: originalURL.path) {
                    try FileManager.default.copyItem(at: originalURL, to: clonedURL)
                    let newAttachment = try UNNotificationAttachment(identifier: UUID().uuidString, url: clonedURL, options: nil)
                    day2Attachments = [newAttachment]
                }
            } catch {
                print("⚠️ Failed to clone attachment for day2: \(error)")
            }
        }
        
        let request1 = UNNotificationRequest(identifier: "\(identifier)-day1", content: content, trigger: trigger1)
        
        do {
            try await center.add(request1)
            print("✅ Scheduled \(identifier)-day1")
        } catch {
            print("❌ Failed to schedule \(identifier)-day1: \(error.localizedDescription)")
        }
        
        // Secondary Reminder (Next Day at 9:30 AM)
        if let scheduledDate = calendar.date(from: dateComponents),
           let nextDay = calendar.date(byAdding: .day, value: 1, to: scheduledDate) {
            var date2 = calendar.dateComponents([.year, .month, .day], from: nextDay)
            date2.hour = 9
            date2.minute = 30
            
            guard let secondDayContent = content.mutableCopy() as? UNMutableNotificationContent else { return }
            secondDayContent.title = "Reminder: \(content.title)"
            secondDayContent.body = "In case you missed it: \(content.body)"
            secondDayContent.attachments = day2Attachments
            
            let trigger2 = UNCalendarNotificationTrigger(dateMatching: date2, repeats: false)
            let request2 = UNNotificationRequest(identifier: "\(identifier)-day2", content: secondDayContent, trigger: trigger2)
            
            do {
                try await center.add(request2)
                print("✅ Scheduled \(identifier)-day2")
            } catch {
                print("❌ Failed to schedule \(identifier)-day2: \(error.localizedDescription)")
            }
        }
    }

    private func downloadImage(from urlString: String) async throws -> UNNotificationAttachment? {
        guard let url = URL(string: urlString) else { return nil }
        
        let (location, _) = try await URLSession.shared.download(from: url)
        
        let tmpDir = FileManager.default.temporaryDirectory
        let tmpFile = tmpDir.appendingPathComponent(UUID().uuidString + ".jpg")
        
        try FileManager.default.moveItem(at: location, to: tmpFile)
        return try UNNotificationAttachment(identifier: UUID().uuidString, url: tmpFile, options: nil)
    }
    
    func cancelNotification(id: String, type: MediaType) {
        guard isProperlyBundled else { return }
        let baseID = type == .movie ? "movie-\(id)" : "tv-\(id)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["\(baseID)-day1", "\(baseID)-day2"])
    }

    func getPendingNotifications() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
    }

    func scheduleAllUpcomingNotifications(onProgress: (@Sendable (String) -> Void)? = nil) async {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        
        let descriptor = FetchDescriptor<MediaItem>()
        guard let allItems = try? context.fetch(descriptor) else { 
            onProgress?("❌ Failed to fetch items")
            return 
        }
        
        let upcomingItems = allItems.filter { $0.isUpcoming }
            .sorted { 
                let date1 = $0.cachedNextAiringDate ?? $0.releaseDate ?? .distantPast
                let date2 = $1.cachedNextAiringDate ?? $1.releaseDate ?? .distantFuture
                return date1 < date2
            }
        
        onProgress?("🔔 Found \(upcomingItems.count) upcoming items")
        
        // System limit is 64 total notifications. We schedule 2 per item.
        let limit = 32 
        let itemsToProcess = upcomingItems.prefix(limit)
        
        for item in itemsToProcess {
            onProgress?("⏳ Processing \(item.title)...")
            
            // Sequential processing with a small breather for the system daemon
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            if item.type == .movie {
                await self.scheduleMovieNotification(id: item.id, title: item.title, releaseDate: item.releaseDate, posterURL: item.posterURL)
            } else if item.type == .tvShow {
                let tv = item.tvShowDetails
                await self.scheduleTVNotification(
                    id: item.id,
                    title: item.title,
                    posterURL: item.posterURL,
                    nextDate: item.cachedNextAiringDate ?? tv?.nextEpisodeDate,
                    nextEpisodeNumber: tv?.nextEpisodeNumber,
                    nextSeasonNumber: tv?.nextSeasonNumber,
                    nextEpisodeTime: tv?.nextEpisodeTime
                )
            }
            onProgress?("✅ Finished \(item.title)")
        }
        onProgress?("🏁 Sync Complete")
    }

    func runNuclearTest() async {
        guard isProperlyBundled else { return }
        let center = UNUserNotificationCenter.current()
        
        print("☢️ Running Nuclear Test (5 unique alerts)...")
        for i in 1...5 {
            let content = UNMutableNotificationContent()
            content.title = "Nuclear Test #\(i)"
            content.body = "Random UUID: \(UUID().uuidString)"
            content.sound = .default
            
            // Trigger 1 hour in future (incrementing)
            let date = Date().addingTimeInterval(TimeInterval(3600 * i))
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
            let request = UNNotificationRequest(identifier: "nuclear-\(UUID().uuidString)", content: content, trigger: trigger)
            try? await center.add(request)
            print("☢️ Added nuclear-\(i)")
        }
    }
    
    func sendTestNotification() {
        guard isProperlyBundled else {
            print("❌ Cannot send test notification: App is not running as a bundle.")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Test: MediaTracker"
        content.subtitle = "Rich Notification"
        content.body = "This is what your alerts will look like! 🍿"
        content.sound = .default
        content.categoryIdentifier = "MOVIE_RELEASE" // Use an existing category to show actions
        
        // Use a generic placeholder or last item poster for test
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier
        
        if actionIdentifier == "MARK_WATCHED_ACTION" {
            guard let itemID = userInfo["ITEM_ID"] as? String,
                  let itemType = userInfo["ITEM_TYPE"] as? String,
                  let container = modelContainer else {
                completionHandler()
                return
            }
            
            let season = userInfo["SEASON_NUMBER"] as? Int
            let episode = userInfo["EPISODE_NUMBER"] as? Int
            
            Task {
                let actionService = BackgroundActionService(modelContainer: container)
                try? await actionService.markAsWatched(itemID: itemID, type: itemType, season: season, episode: episode)
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }
}
