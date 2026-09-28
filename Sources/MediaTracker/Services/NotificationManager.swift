import AppKit
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

    /// Notification prefs default to ON — but `bool(forKey:)` returns false
    /// when nothing was ever stored, so an unset key must read as enabled.
    private func isChannelEnabled(_ key: UserDefaultsKeys) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key.rawValue) != nil else { return true }
        return defaults.bool(forKey: key.rawValue)
    }

    private var areNotificationsEnabled: Bool { isChannelEnabled(.notificationsEnabled) }

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
    
    /// Computes the effective trigger date for a release date, accounting for episode air time or default notification delivery time.
    private func computeEffectiveTriggerDate(from date: Date, time: String? = nil, usesDefaultTime: Bool = true) -> (dateComponents: DateComponents, triggerDate: Date)? {
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

        // 2. Default fallback (movies, or TV without specific air time):
        // If it's still 00:00 local time, use the user's preferred notification delivery time.
        if dateComponents.hour == 0 && dateComponents.minute == 0 {
            let storedTime = UserDefaults.standard.double(forKey: "notifications_time")
            let totalSeconds = storedTime > 0 ? storedTime : (9 * 3600)
            dateComponents.hour = Int(totalSeconds) / 3600
            dateComponents.minute = (Int(totalSeconds) % 3600) / 60
        }

        guard let triggerDate = calendar.date(from: dateComponents) else { return nil }
        return (dateComponents, triggerDate)
    }

    func scheduleMovieNotification(id: String, title: String, releaseDate: Date?, posterURL: String?) async {
        guard isProperlyBundled else { return }
        guard areNotificationsEnabled, isChannelEnabled(.notificationsMovies) else {
            AppLogger.debug("🔕 Skipping notification for \(title): movie channel disabled.", logger: AppLogger.notifications)
            return
        }
        guard let releaseDate = releaseDate,
              let computed = computeEffectiveTriggerDate(from: releaseDate, usesDefaultTime: true),
              computed.triggerDate > Date() else { 
            AppLogger.debug("ℹ️ Skipping notification for \(title): Release date is in the past or nil.", logger: AppLogger.notifications)
            return 
        }
        
        AppLogger.info("🔔 Scheduling notification for movie: \(title) (\(computed.triggerDate))", logger: AppLogger.notifications)
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
        await finalizeSchedule(identifier: identifier, content: content, dateComponents: computed.dateComponents, triggerDate: computed.triggerDate)
    }

    func scheduleTVNotification(id: String, title: String, posterURL: String?, nextDate: Date?, nextEpisodeNumber: Int?, nextSeasonNumber: Int?, nextEpisodeTime: String?) async {
        guard isProperlyBundled else { return }
        guard areNotificationsEnabled, isChannelEnabled(.notificationsTV) else {
            AppLogger.debug("🔕 Skipping notification for \(title): TV channel disabled.", logger: AppLogger.notifications)
            return
        }
        guard let nextDate = nextDate,
              let computed = computeEffectiveTriggerDate(from: nextDate, time: nextEpisodeTime, usesDefaultTime: false),
              computed.triggerDate > Date() else { 
            AppLogger.debug("ℹ️ Skipping notification for \(title): Next air date is in the past or nil.", logger: AppLogger.notifications)
            return 
        }
        
        AppLogger.info("🔔 Scheduling notification for TV show: \(title) (\(computed.triggerDate))", logger: AppLogger.notifications)
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
        await finalizeSchedule(identifier: identifier, content: content, dateComponents: computed.dateComponents, triggerDate: computed.triggerDate)
    }

    /// "Season N ends today — binge watch if you haven't already."
    ///
    /// Fires alongside the per-episode notification for the finale, not instead
    /// of it: the episode ping says something is available, this one says the
    /// season is now complete. Purely additive.
    ///
    /// No poster attachment, so it reads as a different kind of alert in
    /// Notification Centre, and no next-day reminder — the day after a finale is
    /// not news.
    func scheduleSeasonEndNotification(
        id: String,
        title: String,
        seasonNumber: Int,
        finaleAirDate: Date,
        airTime: String?
    ) async {
        guard isProperlyBundled else { return }
        guard areNotificationsEnabled, isChannelEnabled(.notificationsTV) else { return }
        guard let computed = computeEffectiveTriggerDate(from: finaleAirDate, time: airTime, usesDefaultTime: false),
              computed.triggerDate > Date() else { return }

        let identifier = "tv-\(id)-seasonend-S\(seasonNumber)"
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = "Season \(seasonNumber) ends today"
        content.body = "Binge watch if you haven't already."
        content.sound = .default
        // Reuse the TV category so the existing "Mark as Watched" action works
        // on this notification too. EPISODE_NUMBER -1 marks it as a season-level
        // alert, so the action falls back to "next unwatched" rather than
        // resolving a bogus episode.
        content.categoryIdentifier = "TV_EPISODE_RELEASE"
        content.userInfo = [
            "ITEM_ID": id,
            "ITEM_TYPE": "tvShow",
            "SEASON_NUMBER": seasonNumber,
            "EPISODE_NUMBER": -1
        ]

        AppLogger.info("🔔 Scheduling season-end notification: \(title) S\(seasonNumber) (\(computed.triggerDate))", logger: AppLogger.notifications)
        await finalizeSchedule(identifier: identifier, content: content, dateComponents: computed.dateComponents, triggerDate: computed.triggerDate)
    }

    private func finalizeSchedule(identifier: String, content: UNMutableNotificationContent, dateComponents: DateComponents, triggerDate: Date) async {
        guard isProperlyBundled else { return }
        let center = UNUserNotificationCenter.current()

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            AppLogger.debug("🔕 Skipping schedule \(identifier): notifications not authorized.", logger: AppLogger.notifications)
            return
        }
        
        // One ping per item, on the bare base identifier (no -day1/-day2 suffix).
        // The old next-morning "in case you missed it" reminder doubled the request
        // count, and against the 64-request system cap that consumed the entire
        // budget before any other notification type could be scheduled. It also
        // forced the poster attachment to be cloned for a second copy, because the
        // system takes ownership of a file once it has been handed over.
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
            AppLogger.info("✅ Scheduled \(identifier) for \(triggerDate)", logger: AppLogger.notifications)
        } catch {
            AppErrorState.shared.surfaceError("Failed to schedule notification: \(error.localizedDescription)")
        }
    }

    private func downloadImage(from urlString: String) async throws -> UNNotificationAttachment? {
        guard let container = await ImageCache.shared.get(forKey: urlString, targetSize: .thumbMedium) else {
            return nil
        }
        let bitmap = NSBitmapImageRep(cgImage: container.image)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            return nil
        }
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jpg")
        try data.write(to: tmpURL, options: .atomic)
        return try UNNotificationAttachment(identifier: UUID().uuidString, url: tmpURL, options: nil)
    }
    
    func cancelNotification(id: String, type: MediaType) {
        guard isProperlyBundled else { return }
        let baseID = type == .movie ? "movie-\(id)" : "tv-\(id)"
        // Bare identifier is current; the -day1/-day2 pair is what older builds
        // scheduled, so clear those too or they survive as orphaned requests.
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [baseID, "\(baseID)-day1", "\(baseID)-day2"]
        )
    }

    func removeAllPendingNotifications() {
        guard isProperlyBundled else { return }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
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
        guard isProperlyBundled else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.weeklyDigestID])
    }

    /// Re-schedules the weekly digest from Settings (or cancels if disabled).
    /// Also refreshes the counts on app launch.
    func rescheduleWeeklyDigestIfNeeded() async {
        guard isProperlyBundled else { return }
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
        guard isProperlyBundled else { return [] }
        return await UNUserNotificationCenter.current().pendingNotificationRequests()
    }

    func scheduleAllUpcomingNotifications(onProgress: (@Sendable (String) -> Void)? = nil) async {
        guard isProperlyBundled else { return }
        guard let container = modelContainer else { return }
        guard areNotificationsEnabled else {
            AppLogger.debug("🔕 Skipping bulk schedule: notifications disabled.", logger: AppLogger.notifications)
            return
        }
        let center = UNUserNotificationCenter.current()
        let context = ModelContext(container)
        
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { $0.storedIsUpcoming == true }
        )
        guard let upcomingItemsFetched = try? context.fetch(descriptor) else { 
            onProgress?("Failed to fetch items")
            return 
        }

        // Reconcile: drop our pending requests for items that are no longer
        // upcoming (watched, completed, removed) so stale day-1/day-2 pings
        // can't fire. The weekly digest is owned elsewhere — leave it alone.
        let upcomingIDs = Set(upcomingItemsFetched.map(\.id))
        let pending = await center.pendingNotificationRequests()
        var stale: [String] = []
        for request in pending {
            let identifier = request.identifier
            let base: String
            if identifier.hasSuffix("-day1") {
                base = String(identifier.dropLast(5))
            } else if identifier.hasSuffix("-day2") {
                // No longer scheduled. Always stale, whether or not the item is
                // still upcoming, so flag it for removal rather than skipping it.
                stale.append(identifier)
                continue
            } else {
                base = identifier
            }
            let itemID: String?
            if base.hasPrefix("movie-") {
                itemID = String(base.dropFirst(6))
            } else if base.hasPrefix("tv-") {
                itemID = String(base.dropFirst(3))
            } else {
                continue
            }
            if let itemID, !upcomingIDs.contains(itemID) {
                stale.append(identifier)
            }
        }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
            AppLogger.info("🧹 Cleared \(stale.count) stale notification(s).", logger: AppLogger.notifications)
        }
        
        let upcomingItems = upcomingItemsFetched.sorted {
            let date1 = $0.cachedNextAiringDate ?? $0.releaseDate ?? .distantFuture
            let date2 = $1.cachedNextAiringDate ?? $1.releaseDate ?? .distantFuture
            return date1 < date2
        }

        let moviesAllowed = isChannelEnabled(.notificationsMovies)
        let tvAllowed = isChannelEnabled(.notificationsTV)
        let channelFiltered = upcomingItems.filter {
            ($0.type == .movie && moviesAllowed) || ($0.type == .tvShow && tvAllowed)
        }
        
        onProgress?("Found \(channelFiltered.count) upcoming items")
        
        // System limit is 64 pending notifications. One request per item now that
        // the next-morning reminder is gone, so the whole budget covers items and
        // still leaves headroom for the weekly digest and season-end notifications.
        let digestEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.weeklyDigestEnabled.rawValue)

        // Reserve season-end slots *before* spending the remainder on episode
        // pings, otherwise these would push the last item(s) off the end. Capped so
        // a burst of simultaneous finales can't crowd out every episode alert, and
        // windowed so the set shrinks on its own as finales air.
        let seasonEndCap = 6
        let seasonEndWindow: TimeInterval = .days14
        let seasonEndCandidates: [(item: MediaItem, seasonNumber: Int, airDate: Date)] = tvAllowed
            ? channelFiltered.compactMap { item in
                guard item.type == .tvShow,
                      let tv = item.tvShowDetails,
                      let finale = tv.upcomingSeasonFinale(within: seasonEndWindow)
                else { return nil }
                // On Hold means deliberately paused, so skip it. Wishlist is
                // wanted — "binge if you haven't" covers never-started shows.
                // Completed is not a nudge.
                guard item.state != .onHold, item.state != .completed else { return nil }
                return (item, finale.season.seasonNumber, finale.airDate)
            }
            .sorted { $0.airDate < $1.airDate }
            .prefix(seasonEndCap)
            .map { $0 }
            : []

        for candidate in seasonEndCandidates {
            await scheduleSeasonEndNotification(
                id: candidate.item.id,
                title: candidate.item.title,
                seasonNumber: candidate.seasonNumber,
                finaleAirDate: candidate.airDate,
                airTime: candidate.item.tvShowDetails?.nextEpisodeTime
            )
        }
        if !seasonEndCandidates.isEmpty {
            AppLogger.info("🔔 Scheduled \(seasonEndCandidates.count) season-end notification(s).", logger: AppLogger.notifications)
        }

        let limit = (digestEnabled ? 62 : 63) - seasonEndCandidates.count
        let itemsToProcess = channelFiltered.prefix(max(0, limit))
        
        // Process concurrently using TaskGroup with bounded parallelism (max 4 concurrent)
        await withTaskGroup(of: Void.self) { group in
            var activeWorkers = 0
            let maxConcurrent = 4

            for item in itemsToProcess {
                if Task.isCancelled { break }

                if activeWorkers >= maxConcurrent {
                    _ = await group.next()
                    activeWorkers -= 1
                }

                let id = item.id
                let title = item.title
                let type = item.type
                let posterURL = item.effectivePosterURL
                let releaseDate = item.releaseDate
                let tv = item.tvShowDetails
                // Local watch state, not the cached TMDB/TVMaze "next episode" —
                // see TVShowDetails.nextUnwatchedUnairedEpisode().
                let nextEpisode = tv?.nextUnwatchedUnairedEpisode()
                let nextDate = nextEpisode?.airDateAsDate ?? item.cachedNextAiringDate
                let nextEpNum = nextEpisode?.episodeNumber
                let nextSeasonNum = nextEpisode?.seasonNumber
                // Air time still comes from the network metadata: airDateAsDate can
                // land on midnight, and the trigger needs the real broadcast hour.
                let nextTime = tv?.nextEpisodeTime

                activeWorkers += 1
                group.addTask {
                    onProgress?("Processing \(title)...")
                    if type == .movie {
                        await self.scheduleMovieNotification(id: id, title: title, releaseDate: releaseDate, posterURL: posterURL)
                    } else if type == .tvShow {
                        await self.scheduleTVNotification(
                            id: id,
                            title: title,
                            posterURL: posterURL,
                            nextDate: nextDate,
                            nextEpisodeNumber: nextEpNum,
                            nextSeasonNumber: nextSeasonNum,
                            nextEpisodeTime: nextTime
                        )
                    }
                    onProgress?("Finished \(title)")
                }
            }
            await group.waitForAll()
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
