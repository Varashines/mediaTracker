import Foundation
@preconcurrency import UserNotifications

@MainActor
class NotificationManager: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    override init() {
        super.init()
    }
    
    private var isProperlyBundled: Bool {
        return Bundle.main.bundleIdentifier != nil && !Bundle.main.bundlePath.hasSuffix(".xctest")
    }

    func requestPermission() {
        guard isProperlyBundled else {
            print("⚠️ Skipping notification permission request: App is not running from a proper .app bundle (expected in Xcode/SPM environments). Run the installed version for notifications.")
            return
        }
        
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("✅ Notification permission granted.")
                } else if let error = error {
                    print("❌ Notification permission error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func scheduleMovieNotification(item: MediaItem) {
        guard isProperlyBundled else { return }
        guard let releaseDate = item.releaseDate, releaseDate > Date() else { return }
        
        let identifier = "movie-\(item.id)"
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.subtitle = "Movie Release"
        content.body = "Is out today! Enjoy the premiere. 🍿"
        content.sound = .default
        
        Task {
            if let posterURL = item.posterURL, let attachment = try? await downloadImage(from: posterURL) {
                content.attachments = [attachment]
            }
            finalizeSchedule(identifier: identifier, content: content, date: releaseDate)
        }
    }
    
    func scheduleTVNotification(item: MediaItem) {
        guard isProperlyBundled else { return }
        guard let tv = item.tvShowDetails, let nextDate = item.nextAiringDate, nextDate > Date() else { return }
        
        let identifier = "tv-\(item.id)"
        let content = UNMutableNotificationContent()
        content.title = item.title
        
        let season = tv.nextSeasonNumber ?? 0
        let episode = tv.nextEpisodeNumber ?? 0
        
        if episode == 1 {
            content.subtitle = "Season Premiere"
            content.body = "Season \(season) starts today! 📺"
        } else {
            content.subtitle = "New Episode"
            content.body = "Season \(season), Episode \(episode) is available now."
        }
        content.sound = .default
        
        Task {
            if let posterURL = item.posterURL, let attachment = try? await downloadImage(from: posterURL) {
                content.attachments = [attachment]
            }
            finalizeSchedule(identifier: identifier, content: content, date: nextDate, time: tv.nextEpisodeTime)
        }
    }
    
    private func finalizeSchedule(identifier: String, content: UNMutableNotificationContent, date: Date, time: String? = nil) {
        guard isProperlyBundled else { return }
        let center = UNUserNotificationCenter.current()
        
        var date1 = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        
        if date1.hour == 0 && date1.minute == 0 {
            date1.hour = 13
            date1.minute = 30
        }
        
        let trigger1 = UNCalendarNotificationTrigger(dateMatching: date1, repeats: false)
        let request1 = UNNotificationRequest(identifier: "\(identifier)-day1", content: content, trigger: trigger1)
        
        center.add(request1)
        
        if let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: date) {
            var date2 = Calendar.current.dateComponents([.year, .month, .day], from: nextDay)
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
    
    func cancelNotification(for item: MediaItem) {
        guard isProperlyBundled else { return }
        let baseID = item.type == .movie ? "movie-\(item.id)" : "tv-\(item.id)"
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
        
        // Use a generic placeholder or last item poster for test
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
