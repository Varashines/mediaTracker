import Foundation
import SwiftData
@preconcurrency import UserNotifications

@MainActor
class NotificationManager: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    private var modelContainer: ModelContainer?
    
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
    
    func scheduleMovieNotification(id: String, title: String, releaseDate: Date?, posterURL: String?) {
        guard isProperlyBundled else { return }
        guard let releaseDate = releaseDate, releaseDate > Date() else { return }
        
        let identifier = "movie-\(id)"
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = "Movie Release"
        content.body = "Is out today! Enjoy the premiere. 🍿"
        content.sound = .default
        content.categoryIdentifier = "MOVIE_RELEASE"
        content.userInfo = ["ITEM_ID": id, "ITEM_TYPE": "movie"]
        
        Task {
            if let posterURL = posterURL, let attachment = try? await downloadImage(from: posterURL) {
                content.attachments = [attachment]
            }
            finalizeSchedule(identifier: identifier, content: content, date: releaseDate)
        }
    }
    
    func scheduleTVNotification(id: String, title: String, posterURL: String?, nextDate: Date?, nextEpisodeNumber: Int?, nextSeasonNumber: Int?, nextEpisodeTime: String?) {
        guard isProperlyBundled else { return }
        guard let nextDate = nextDate, nextDate > Date() else { return }
        
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
        
        Task {
            if let posterURL = posterURL, let attachment = try? await downloadImage(from: posterURL) {
                content.attachments = [attachment]
            }
            finalizeSchedule(identifier: identifier, content: content, date: nextDate, time: nextEpisodeTime)
        }
    }
    
    private func finalizeSchedule(identifier: String, content: UNMutableNotificationContent, date: Date, time: String? = nil) {
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
        // We use 09:00 AM as a more sensible "day-of" notification time than 13:30.
        // If DateUtils parsing provided a specific drop time (like 09:30 AM IST for Apple TV+), 
        // it will already be in dateComponents and we trust it.
        if dateComponents.hour == 0 && dateComponents.minute == 0 {
            dateComponents.hour = 9
            dateComponents.minute = 0
        }
        
        let trigger1 = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request1 = UNNotificationRequest(identifier: "\(identifier)-day1", content: content, trigger: trigger1)
        
        center.add(request1)
        
        // Secondary Reminder (Next Day at 9:30 AM)
        if let scheduledDate = calendar.date(from: dateComponents),
           let nextDay = calendar.date(byAdding: .day, value: 1, to: scheduledDate) {
            var date2 = calendar.dateComponents([.year, .month, .day], from: nextDay)
            date2.hour = 9
            date2.minute = 30
            
            guard let secondDayContent = content.mutableCopy() as? UNMutableNotificationContent else { return }
            secondDayContent.title = "Reminder: \(content.title)"
            secondDayContent.body = "In case you missed it: \(content.body)"
            
            let trigger2 = UNCalendarNotificationTrigger(dateMatching: date2, repeats: false)
            let request2 = UNNotificationRequest(identifier: "\(identifier)-day2", content: secondDayContent, trigger: trigger2)
            
            center.add(request2)
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
