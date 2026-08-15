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

    func requestPermission() async {
        guard isProperlyBundled else {
            AppLogger.warning("⚠️ Skipping notification permission request: App is not running from a proper .app bundle.", logger: AppLogger.notifications)
            return
        }

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let markWatchedAction = UNNotificationAction(identifier: "MARK_WATCHED_ACTION", title: "Mark as Watched", options: [])
        let movieCategory = UNNotificationCategory(identifier: "MOVIE_RELEASE", actions: [markWatchedAction], intentIdentifiers: [], options: [])
        let tvCategory = UNNotificationCategory(identifier: "TV_EPISODE_RELEASE", actions: [markWatchedAction], intentIdentifiers: [], options: [])
        center.setNotificationCategories([movieCategory, tvCategory])

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                AppLogger.info("✅ Notification permission granted.", logger: AppLogger.notifications)
            }
        } catch {
            AppErrorState.shared.surfaceError("Notification permission error: \(error.localizedDescription)")
        }
    }
    
    func scheduleMovieNotification(id: String, title: String, releaseDate: Date?, posterURL: String?) async {
        guard isProperlyBundled else { return }
        guard let releaseDate = releaseDate, releaseDate > Date() else { 
            AppLogger.debug("ℹ️ Skipping notification for \(title): Release date is in the past or nil.", logger: AppLogger.notifications)
            return 
        }
        
        AppLogger.info("🔔 Scheduling notification for movie: \(title) (\(releaseDate))", logger: AppLogger.notifications)
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
            AppLogger.debug("ℹ️ Skipping notification for \(title): Next air date is in the past or nil.", logger: AppLogger.notifications)
            return 
        }
        
        AppLogger.info("🔔 Scheduling notification for TV show: \(title) (\(nextDate))", logger: AppLogger.notifications)
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
            content.subtitle = "Premiere"
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

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            AppLogger.debug("🔕 Skipping schedule \(identifier): notifications not authorized.", logger: AppLogger.notifications)
            return
        }
        
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
            let storedTime = UserDefaults.standard.double(forKey: "notifications_time")
            let totalSeconds = storedTime > 0 ? storedTime : (9 * 3600)
            dateComponents.hour = Int(totalSeconds) / 3600
            dateComponents.minute = (Int(totalSeconds) % 3600) / 60
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
                AppLogger.warning("⚠️ Failed to clone attachment for day2: \(error)", logger: AppLogger.notifications)
            }
        }
        
        let request1 = UNNotificationRequest(identifier: "\(identifier)-day1", content: content, trigger: trigger1)
        
        do {
            try await center.add(request1)
            AppLogger.info("✅ Scheduled \(identifier)-day1", logger: AppLogger.notifications)
        } catch {
            AppErrorState.shared.surfaceError("Failed to schedule notification: \(error.localizedDescription)")
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
                AppLogger.info("✅ Scheduled \(identifier)-day2", logger: AppLogger.notifications)
            } catch {
                AppErrorState.shared.surfaceError("Failed to schedule reminder: \(error.localizedDescription)")
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

    // MARK: - Weekly Digest

    private static let weeklyDigestID = "weekly-digest"

    /// Schedules the next weekly digest (one-shot so the counts are computed
    /// fresh at schedule time; re-scheduled on launch and when the user taps it).
    func scheduleWeeklyDigest(weekday: Int, hour: Int, minute: Int) async {
        guard isProperlyBundled else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.weeklyDigestID])

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        guard let container = modelContainer else { return }

        let service = WeeklyDigestService(modelContainer: container)
        let digest = await service.digest()

        let content = UNMutableNotificationContent()
        content.title = "Your Week in Review"
        content.body = digestBody(digest)
        content.sound = .default
        content.userInfo = ["ITEM_TYPE": "weekly_digest"]

        let calendar = Calendar.current
        let todayWeekday = calendar.component(.weekday, from: Date())
        var daysAhead = weekday - todayWeekday
        if daysAhead <= 0 { daysAhead += 7 }
        guard let next = calendar.date(byAdding: .day, value: daysAhead, to: Date()) else { return }

        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: next)
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: Self.weeklyDigestID, content: content, trigger: trigger)

        do {
            try await center.add(request)
            AppLogger.info("✅ Scheduled weekly digest: \(digest.shows) shows, \(digest.movies) movies", logger: AppLogger.notifications)
        } catch {
            AppErrorState.shared.surfaceError("Failed to schedule weekly digest: \(error.localizedDescription)")
        }
    }

    func cancelWeeklyDigest() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.weeklyDigestID])
    }

    /// Re-schedules the weekly digest from Settings (or cancels if disabled).
    /// Also refreshes the counts on app launch.
    func rescheduleWeeklyDigestIfNeeded() async {
        guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.weeklyDigestEnabled.rawValue) else {
            cancelWeeklyDigest()
            return
        }
        let weekday = UserDefaults.standard.integer(forKey: UserDefaultsKeys.weeklyDigestWeekday.rawValue)
        let storedTime = UserDefaults.standard.double(forKey: UserDefaultsKeys.weeklyDigestTime.rawValue)
        let totalSeconds = storedTime > 0 ? storedTime : (19 * 3600)
        await scheduleWeeklyDigest(
            weekday: weekday == 0 ? 1 : weekday,
            hour: Int(totalSeconds) / 3600,
            minute: (Int(totalSeconds) % 3600) / 60
        )
    }

    private func digestBody(_ digest: WeeklyDigest) -> String {
        var parts = [
            "\(digest.shows) show\(digest.shows == 1 ? "" : "s")",
            "\(digest.movies) movie\(digest.movies == 1 ? "" : "s")"
        ]
        if !digest.topShows.isEmpty {
            parts.append("including \(digest.topShows.joined(separator: ", "))")
        }
        return "You watched \(parts.joined(separator: " · ")) this week."
    }

    func getPendingNotifications() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
    }

    func scheduleAllUpcomingNotifications(onProgress: (@Sendable (String) -> Void)? = nil) async {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { $0.storedIsUpcoming == true }
        )
        guard let upcomingItemsFetched = try? context.fetch(descriptor) else { 
            onProgress?("Failed to fetch items")
            return 
        }
        
        let upcomingItems = upcomingItemsFetched.sorted { 
            let date1 = $0.cachedNextAiringDate ?? $0.releaseDate ?? .distantPast
            let date2 = $1.cachedNextAiringDate ?? $1.releaseDate ?? .distantFuture
            return date1 < date2
        }
        
        onProgress?("Found \(upcomingItems.count) upcoming items")
        
        // System limit is 64 total notifications. We schedule 2 per item.
        let limit = 32 
        let itemsToProcess = upcomingItems.prefix(limit)
        
        for item in itemsToProcess {
            if Task.isCancelled { break }
            onProgress?("Processing \(item.title)...")
            
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
            onProgress?("Finished \(item.title)")
        }
        onProgress?("Sync Complete")
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
        } else if userInfo["ITEM_TYPE"] as? String == "weekly_digest" {
            // Refresh next week's counts when the digest is opened.
            Task {
                await self.rescheduleWeeklyDigestIfNeeded()
                completionHandler()
            }
        } else {
            // Navigate to the item when notification body is tapped
            if let itemID = userInfo["ITEM_ID"] as? String {
                NavigationRouter.shared.pendingSpotlightItemID = itemID
            }
            completionHandler()
        }
    }
}
